const std = @import("std");
const rc = @import("render_core.zig");
const c = rc.c;

// Zig 0.16 moved file IO behind std.Io (needs an Io instance to construct;
// std.posix.read explicitly refuses Windows in this version, and the only
// Windows file-open primitive left in std lives inside Io.Threaded itself, so
// there is no lighter std-native path on this platform). libc is already
// linked and version-stable — same choice configuration_toml.zig made for the
// same reason.
const libc = @cImport({
    @cInclude("stdio.h");
});

// ke_render_core::load_shader — resolves a shader by logical name + stage to a
// device-ready module, without the caller ever naming a path or a format. The
// core asks the device for its accepted language (WGSL/SPIR-V/MSL/DXIL), maps
// that to a file extension, and reads "<shader_dir>/<name>.<stage>.<ext>" — a
// file ke_compile_slang_shader (CMake) already produced at build time. This
// loads a build-time artifact; it never invokes a shader compiler, so the
// PSO-affecting shader set stays statically derivable (§6 doctrine) even
// though the read happens at runtime. Deduped by resolved path through the
// core's shader cache, same shape as mesh/texture/material.

fn extForLanguage(lang: c.ke_gpu_shader_language) []const u8 {
    return switch (lang) {
        c.KE_GPU_SHADER_LANG_WGSL => "wgsl",
        c.KE_GPU_SHADER_LANG_SPIRV => "spv",
        c.KE_GPU_SHADER_LANG_MSL => "metal",
        c.KE_GPU_SHADER_LANG_DXIL => "dxil",
        else => "wgsl",
    };
}

// `stage` is a bitmask type at the ABI level, but a shader module is always
// exactly one stage — a combination is a caller error, not a valid request.
fn stageSuffix(stage: c.ke_gpu_shader_stage) ?[]const u8 {
    return switch (stage) {
        c.KE_GPU_SHADER_STAGE_VERTEX => "vs",
        c.KE_GPU_SHADER_STAGE_FRAGMENT => "fs",
        c.KE_GPU_SHADER_STAGE_COMPUTE => "cs",
        else => null,
    };
}

pub fn loadShader(self: [*c]c.ke_render_core, name: [*c]const u8, stage: c.ke_gpu_shader_stage, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_shader_module {
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

    const fp = libc.fopen(path.ptr, "rb") orelse {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_FOUND, "load_shader: shader file not found", @src().file, @intCast(@src().line), null);
        return c.KE_GPU_INVALID_HANDLE;
    };
    defer _ = libc.fclose(fp);
    _ = libc.fseek(fp, 0, libc.SEEK_END);
    const size_signed = libc.ftell(fp);
    _ = libc.fseek(fp, 0, libc.SEEK_SET);
    if (size_signed < 0) {
        c.ke_error_set(out_error, &c.KE_ERROR_IO, "load_shader: failed to size shader file", @src().file, @intCast(@src().line), null);
        return c.KE_GPU_INVALID_HANDLE;
    }
    const size: usize = @intCast(size_signed);
    const bytes = rc.gpa.alloc(u8, size) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "load_shader: shader buffer allocation failed", @src().file, @intCast(@src().line), null);
        return c.KE_GPU_INVALID_HANDLE;
    };
    defer rc.gpa.free(bytes);
    if (libc.fread(bytes.ptr, 1, size, fp) != size) {
        c.ke_error_set(out_error, &c.KE_ERROR_IO, "load_shader: failed to read shader file", @src().file, @intCast(@src().line), null);
        return c.KE_GPU_INVALID_HANDLE;
    }

    const module = st.device.create_shader_module.?(st.device, &c.ke_gpu_shader_module_params{
        .code = bytes.ptr,
        .byte_size = bytes.len,
        .entry_point = name,
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

// ke_resource_cache destroy_fn: fires at refcount zero (never, in practice — no
// pass releases a shader) and at cache teardown, for every shader still resident.
pub fn destroyShaderResource(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.shader_store.remove(handle)) |module| {
        st.device.destroy_shader_module.?(st.device, module);
    }
}
