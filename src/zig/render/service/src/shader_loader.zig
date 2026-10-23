//! Loads shader modules by name from the service's shader directory and caches them by path.

const std = @import("std");
const rc = @import("render_service.zig");
const c = rc.c;
const R = rc.R;
const log = std.log.scoped(.render_service);

const shader_files = @import("shader_files").ShaderFiles(c);

/// Any language the file does not list falls back to the WGSL extension.
fn extForLanguage(lang: c.ke_gpu_shader_language) []const u8 {
    return switch (lang) {
        c.KE_GPU_SHADER_LANG_WGSL => "wgsl",
        c.KE_GPU_SHADER_LANG_SPIRV => "spv",
        c.KE_GPU_SHADER_LANG_MSL => "metal",
        c.KE_GPU_SHADER_LANG_DXIL => "dxil",
        else => "wgsl",
    };
}

/// Null unless the stage is exactly one of vertex, fragment or compute.
fn stageSuffix(stage: c.ke_gpu_shader_stage) ?[]const u8 {
    return switch (stage) {
        c.KE_GPU_SHADER_STAGE_VERTEX => "vs",
        c.KE_GPU_SHADER_STAGE_FRAGMENT => "fs",
        c.KE_GPU_SHADER_STAGE_COMPUTE => "cs",
        else => null,
    };
}

/// The service's shader-loading slot. The file read is "<shader dir>/<name>.<vs|fs|cs>.<ext>", and
/// the resolved path is the cache key. A cache hit writes the stored module without reading the
/// disk. On a miss the module is created on the device, stored, registered with the cache and
/// cached under the path. A stage that is not exactly one or a path too long for its buffer fails
/// as an invalid argument; a file that does not open as not found; one that cannot be sized or
/// fully read as I/O; a file buffer or a store that cannot be allocated as out of memory, a module
/// already created being destroyed on the device first. A failure of the device is its own code.
pub fn loadShader(self: [*c]c.ke_render_service, name: [*c]const u8, stage: c.ke_gpu_shader_stage, out_module: [*c]c.ke_gpu_shader_module) callconv(.c) c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = c.KE_GPU_INVALID_HANDLE;
    if (self == null or name == null) return R.code(error.InvalidArgument);
    out.* = load(rc.coreOf(self), name, stage) catch |err| return R.code(err);
    return R.ok;
}

fn load(st: *rc.CoreState, name: [*c]const u8, stage: c.ke_gpu_shader_stage) R.Error!c.ke_gpu_shader_module {
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

    var cached: c.ke_resource_handle = c.KE_HANDLE_NONE;
    if (st.shader_cache.try_get_cached.?(st.shader_cache, path.ptr, &cached)) {
        return st.shader_store.get(cached).?.*;
    }

    const bytes = try shader_files.read(rc.gpa, path);
    defer rc.gpa.free(bytes);

    var module: c.ke_gpu_shader_module = c.KE_GPU_INVALID_HANDLE;
    try R.check(st.device.create_shader_module.?(st.device, &c.ke_gpu_shader_module_params{
        .code = bytes.ptr,
        .byte_size = bytes.len,
        .label = name,
    }, &module));
    errdefer st.device.destroy_shader_module.?(st.device, module);

    const bits = st.shader_store.insert(module);
    if (bits == c.KE_HANDLE_NONE) return error.OutOfMemory;
    _ = st.shader_cache.register_resource.?(st.shader_cache, bits);
    _ = st.shader_cache.cache_insert.?(st.shader_cache, path.ptr, bits);
    return module;
}

/// The destroy callback `shader_cache` calls for a module registered by `loadShader`. The context
/// is the `CoreState` of the service, and a handle that `shader_store` no longer holds is ignored.
pub fn destroyShaderResource(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.shader_store.remove(handle)) |module| {
        st.device.destroy_shader_module.?(st.device, module);
    }
}
