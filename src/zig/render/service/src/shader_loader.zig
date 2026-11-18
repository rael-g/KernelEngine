//! Loads shader modules by name from the service's shader directory and caches them by path.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_io = @import("abi_io");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_handles = @import("abi_render_handles");
const std = @import("std");
const rc = @import("render_service.zig");
const abi_render = @import("abi_render");
const abi_resource_cache = @import("abi_resource_cache");
const abi_result = @import("abi_result");
const R = rc.R;
const log = std.log.scoped(.render_service);

/// A read of a shader file in flight, pushed onto the service's `shader_reads` and freed only with
/// the service. The thread that sets `taken` from false owns `request` until it clears `taken` again
/// or collects the request, after which `request` is null and the read stays taken.
pub const Read = struct {
    next: ?*Read,
    path: [:0]u8,
    request: std.atomic.Value(?*abi_io.c.ke_io_request),
    taken: std.atomic.Value(bool),
};

fn findRead(st: *rc.CoreState, path: []const u8) ?*Read {
    var it = st.shader_reads.load(.acquire);
    while (it) |read| : (it = read.next) {
        if (read.request.load(.acquire) != null and std.mem.eql(u8, read.path, path)) return read;
    }
    return null;
}

fn startRead(st: *rc.CoreState, path: [:0]const u8) R.Error!*Read {
    const read = try rc.gpa.create(Read);
    errdefer rc.gpa.destroy(read);
    const owned = try rc.gpa.dupeZ(u8, path);
    errdefer rc.gpa.free(owned);
    var request: ?*abi_io.c.ke_io_request = null;
    R.check(st.io.read_file.?(st.io, path.ptr, &request)) catch |err| {
        log.warn("load_shader: reading {s} failed: {t}", .{ path, err });
        return err;
    };
    read.* = .{ .next = null, .path = owned, .request = .init(request), .taken = .init(false) };
    var head = st.shader_reads.load(.monotonic);
    while (true) {
        read.next = head;
        head = st.shader_reads.cmpxchgWeak(head, read, .release, .monotonic) orelse break;
    }
    return read;
}

/// Collects the read of `path`, starting it when none is in flight. Fails as pending when the read
/// is being collected by another thread or cannot be waited on from this one.
fn readFile(st: *rc.CoreState, path: [:0]const u8) R.Error![]u8 {
    const read = findRead(st, path) orelse try startRead(st, path);
    if (read.taken.cmpxchgStrong(false, true, .acquire, .monotonic) != null) return error.Pending;
    const request = read.request.load(.acquire) orelse return error.Pending;
    var result: abi_io.c.ke_io_result = undefined;
    const code = st.io.wait.?(st.io, request, &result);
    if (code == R.code(error.NotSupported)) {
        read.taken.store(false, .release);
        return error.Pending;
    }
    read.request.store(null, .release);
    R.check(code) catch |err| {
        log.warn("load_shader: reading {s} failed: {t}", .{ path, err });
        return err;
    };
    return @as([*]u8, @ptrCast(result.bytes.?))[0..@intCast(result.size)];
}

/// Collects every read still in flight and frees the list; called when the service is destroyed,
/// on the thread that may wait.
pub fn releaseReads(st: *rc.CoreState) void {
    var it = st.shader_reads.swap(null, .acquire);
    while (it) |read| {
        it = read.next;
        if (read.request.load(.acquire)) |request| {
            var result: abi_io.c.ke_io_result = undefined;
            if (st.io.wait.?(st.io, request, &result) == R.ok) st.io.free_bytes.?(st.io, result.bytes);
        }
        rc.gpa.free(read.path);
        rc.gpa.destroy(read);
    }
}

/// Any language the file does not list falls back to the WGSL extension.
fn extForLanguage(lang: abi_render_gpu.c.ke_gpu_shader_language) []const u8 {
    return switch (lang) {
        abi_render_gpu.c.KE_GPU_SHADER_LANG_WGSL => "wgsl",
        abi_render_gpu.c.KE_GPU_SHADER_LANG_SPIRV => "spv",
        abi_render_gpu.c.KE_GPU_SHADER_LANG_MSL => "metal",
        abi_render_gpu.c.KE_GPU_SHADER_LANG_DXIL => "dxil",
        else => "wgsl",
    };
}

/// Null unless the stage is exactly one of vertex, fragment or compute.
fn stageSuffix(stage: abi_asset_resolver.c.ke_gpu_shader_stage) ?[]const u8 {
    return switch (stage) {
        abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX => "vs",
        abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT => "fs",
        abi_render_gpu.c.KE_GPU_SHADER_STAGE_COMPUTE => "cs",
        else => null,
    };
}

/// The service's shader-loading slot. The file read is "<shader dir>/<name>.<vs|fs|cs>.<ext>", and
/// the resolved path is the cache key. A cache hit writes the stored module without reading the
/// disk. On a miss the module is created on the device, stored, registered with the cache and
/// cached under the path; the read is collected by `readFile`, which fails as pending while it goes
/// on. A stage that is not exactly one or a path too long for its buffer fails
/// as an invalid argument; a file that does not open as not found; one that cannot be sized or
/// fully read as I/O; a file buffer or a store that cannot be allocated as out of memory, a module
/// already created being destroyed on the device first. A failure of the device is its own code.
pub fn loadShader(self: [*c]abi_render.c.ke_render_service, name: [*c]const u8, stage: abi_asset_resolver.c.ke_gpu_shader_stage, out_module: [*c]abi_asset_resolver.c.ke_gpu_shader_module) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    if (self == null or name == null) return R.code(error.InvalidArgument);
    out.* = load(rc.coreOf(self), name, stage) catch |err| return R.code(err);
    return R.ok;
}

fn load(st: *rc.CoreState, name: [*c]const u8, stage: abi_asset_resolver.c.ke_gpu_shader_stage) R.Error!abi_asset_resolver.c.ke_gpu_shader_module {
    const suffix = stageSuffix(stage) orelse {
        log.warn("load_shader: the stage of {s} must be exactly one of vertex, fragment or compute", .{std.mem.span(name)});
        return error.InvalidArgument;
    };
    const ext = extForLanguage(st.device.shader_language.?(st.device));

    var path_buf: [1024]u8 = undefined;
    const name_span = std.mem.span(name);
    const path = std.fmt.bufPrintZ(&path_buf, "{s}/{s}.{s}.{s}", .{ st.shader_dir, name_span, suffix, ext }) catch {
        log.warn("load_shader: the resolved path of {s} is too long", .{name_span});
        return error.InvalidArgument;
    };

    var cached: abi_resource_cache.c.ke_resource_handle = abi_render_handles.c.KE_HANDLE_NONE;
    if (st.shader_cache.try_get_cached.?(st.shader_cache, path.ptr, &cached)) {
        return st.shader_store.get(cached).?.*;
    }

    const bytes = try readFile(st, path);
    defer st.io.free_bytes.?(st.io, bytes.ptr);
    if (st.shader_cache.try_get_cached.?(st.shader_cache, path.ptr, &cached)) {
        return st.shader_store.get(cached).?.*;
    }

    var module: abi_asset_resolver.c.ke_gpu_shader_module = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    try R.check(st.device.create_shader_module.?(st.device, &abi_render_gpu.c.ke_gpu_shader_module_params{
        .code = bytes.ptr,
        .byte_size = bytes.len,
        .label = name,
    }, &module));
    errdefer st.device.destroy_shader_module.?(st.device, module);

    const bits = st.shader_store.insert(module);
    if (bits == abi_render_handles.c.KE_HANDLE_NONE) return error.OutOfMemory;
    _ = st.shader_cache.register_resource.?(st.shader_cache, bits);
    _ = st.shader_cache.cache_insert.?(st.shader_cache, path.ptr, bits);
    return module;
}

/// The destroy callback `shader_cache` calls for a module registered by `loadShader`. The context
/// is the `CoreState` of the service, and a handle that `shader_store` no longer holds is ignored.
pub fn destroyShaderResource(handle: abi_resource_cache.c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.shader_store.remove(handle)) |module| {
        st.device.destroy_shader_module.?(st.device, module);
    }
}
