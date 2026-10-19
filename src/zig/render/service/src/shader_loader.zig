//! Loads shader modules by name from the service's shader directory and caches them by path.

const std = @import("std");
const rc = @import("render_service.zig");
const c = rc.c;

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
/// the resolved path is the cache key. A cache hit returns the stored module without reading the
/// disk and leaves the error out-parameter untouched. On a miss the module is created on the
/// device, stored, registered with the cache and cached under the path. Every failure returns the
/// invalid handle and fills the error: invalid argument for a stage that is not exactly one or a
/// path too long for its buffer; not found when the file does not open; I/O when it cannot be
/// sized or fully read; out of memory when the file buffer or the store cannot be allocated, in
/// which case a module already created is destroyed on the device first. A failure of the device
/// call is the device's own error.
pub fn loadShader(self: [*c]c.ke_render_service, name: [*c]const u8, stage: c.ke_gpu_shader_stage, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_shader_module {
    const st = rc.coreOf(self);

    const suffix = stageSuffix(stage) orelse {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "load_shader: stage must be exactly one of VERTEX/FRAGMENT/COMPUTE", @src().file, @intCast(@src().line), null);
        return c.KE_GPU_INVALID_HANDLE;
    };
    const ext = extForLanguage(st.device.shader_language.?(st.device));

    var path_buf: [1024]u8 = undefined;
    const name_span = std.mem.span(name);
    const path = std.fmt.bufPrintZ(&path_buf, "{s}/{s}.{s}.{s}", .{ st.shader_dir, name_span, suffix, ext }) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "load_shader: resolved path too long", @src().file, @intCast(@src().line), null);
        return c.KE_GPU_INVALID_HANDLE;
    };

    var cached: c.ke_resource_handle = c.KE_HANDLE_NONE;
    if (st.shader_cache.try_get_cached.?(st.shader_cache, path.ptr, &cached)) {
        return st.shader_store.get(cached).?.*;
    }

    const bytes = shader_files.read(rc.gpa, path, out_error) orelse return c.KE_GPU_INVALID_HANDLE;
    defer rc.gpa.free(bytes);

    const module = st.device.create_shader_module.?(st.device, &c.ke_gpu_shader_module_params{
        .code = bytes.ptr,
        .byte_size = bytes.len,
        .label = name,
    }, out_error);
    if (module == c.KE_GPU_INVALID_HANDLE) return module;

    const bits = st.shader_store.insert(module);
    if (bits == c.KE_HANDLE_NONE) {
        st.device.destroy_shader_module.?(st.device, module);
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "load_shader: shader store insert failed", @src().file, @intCast(@src().line), null);
        return c.KE_GPU_INVALID_HANDLE;
    }
    _ = st.shader_cache.register_resource.?(st.shader_cache, bits, null);
    _ = st.shader_cache.cache_insert.?(st.shader_cache, path.ptr, bits, null);
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
