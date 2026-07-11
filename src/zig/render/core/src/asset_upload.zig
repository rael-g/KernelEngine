const std = @import("std");
const rc = @import("render_core.zig");
const c = rc.c;

// Mesh/texture/material upload + the material bind-group system (set 1). This is
// the asset-ingestion surface a game calls once per unique mesh/texture/material
// at load time — distinct from the per-frame deferred-upload path
// (frame_lifecycle.zig's uploadBuffer), which every pass calls every frame.
//
// Every resource here is owned by a ke_resource_cache (one per kind, held on the
// CoreState). An upload inserts into the matching generational slot map, then
// registers the handle with the cache (refcount 1) and records `key` for future
// dedup lookups — `key` is required, not an opt-in: there is no uncached upload
// path, so nothing a game does can silently duplicate GPU memory. Callers with
// no natural path (procedural content, inline scene-authored materials) key by
// their own generation parameters instead (see render_core.h's per-slot docs).
// release drops a reference; at zero the cache fires the destroy_fn below,
// which removes the slot and frees the GPU objects.

// ── dedup helper ────────────────────────────────────────────────────────────

fn keyValid(key: [*c]const u8) bool {
    return key != null and key[0] != 0;
}

// On a keyed hit returns the cached handle bits (already retained by the cache);
// otherwise KE_HANDLE_NONE, meaning the caller must build the resource.
fn tryCached(cache: *c.ke_resource_cache, key: [*c]const u8) u32 {
    var out: c.ke_resource_handle = c.KE_HANDLE_NONE;
    if (cache.try_get_cached.?(cache, key, &out)) return out;
    return c.KE_HANDLE_NONE;
}

// Registers a freshly-built resource (refcount 1) and records the key for
// future dedup lookups.
fn registerCached(cache: *c.ke_resource_cache, key: [*c]const u8, bits: u32) void {
    _ = cache.register_resource.?(cache, bits, null);
    _ = cache.cache_insert.?(cache, key, bits, null);
}

// ── mesh ────────────────────────────────────────────────────────────────────

pub fn uploadMesh(self: [*c]c.ke_render_core, key: [*c]const u8, vertices: ?*const anyopaque, vertices_size: usize, indices: [*c]const u16, index_count: u32, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_mesh_handle {
    const st = rc.coreOf(self);
    if (!keyValid(key)) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "upload_mesh requires a non-empty key", @src().file, @intCast(@src().line), null);
        return .{ .bits = c.KE_HANDLE_NONE };
    }

    const cached = tryCached(st.mesh_cache, key);
    if (cached != c.KE_HANDLE_NONE) return .{ .bits = cached };

    const vbo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .initial_data = vertices,
        .size = vertices_size,
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (vbo == c.KE_GPU_INVALID_HANDLE) return .{ .bits = c.KE_HANDLE_NONE };

    const ibo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .initial_data = @ptrCast(indices),
        .size = index_count * @sizeOf(u16),
        .usage = c.KE_GPU_BUFFER_USAGE_INDEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (ibo == c.KE_GPU_INVALID_HANDLE) {
        st.device.destroy_buffer.?(st.device, vbo);
        return .{ .bits = c.KE_HANDLE_NONE };
    }

    const bits = st.mesh_store.insert(.{ .vbo = vbo, .ibo = ibo, .index_count = index_count });
    if (bits == c.KE_HANDLE_NONE) {
        st.device.destroy_buffer.?(st.device, vbo);
        st.device.destroy_buffer.?(st.device, ibo);
        return .{ .bits = c.KE_HANDLE_NONE };
    }
    registerCached(st.mesh_cache, key, bits);
    return .{ .bits = bits };
}

pub fn meshBuffers(self: [*c]c.ke_render_core, h: c.ke_mesh_handle, out_vbo: [*c]c.ke_gpu_buffer, out_ibo: [*c]c.ke_gpu_buffer, out_index_count: [*c]u32) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    const m = st.meshAt(h) orelse return 0;
    out_vbo.* = m.vbo;
    out_ibo.* = m.ibo;
    out_index_count.* = m.index_count;
    return 1;
}

pub fn setClearColor(self: [*c]c.ke_render_core, r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    rc.coreOf(self).clear_color = .{ r, g, b, a };
}

// ── texture / cubemap ───────────────────────────────────────────────────────

pub fn uploadTexture(self: [*c]c.ke_render_core, key: [*c]const u8, width: u32, height: u32, rgba: ?*const anyopaque, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_texture_handle {
    const st = rc.coreOf(self);
    if (!keyValid(key)) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "upload_texture requires a non-empty key", @src().file, @intCast(@src().line), null);
        return .{ .bits = c.KE_HANDLE_NONE };
    }

    const cached = tryCached(st.texture_cache, key);
    if (cached != c.KE_HANDLE_NONE) return .{ .bits = cached };

    const tex = st.device.create_texture.?(st.device, &c.ke_gpu_texture_params{
        .width = width,
        .height = height,
        .depth_or_array_layers = 1,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .usage = c.KE_GPU_TEXTURE_USAGE_SAMPLED,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = rgba,
        .initial_data_size = width * height * 4,
    });
    if (tex == c.KE_GPU_INVALID_HANDLE) return .{ .bits = c.KE_HANDLE_NONE };

    const view = st.device.create_texture_view.?(st.device, tex, &c.ke_gpu_texture_view_params{
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .aspect = c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    });

    const bits = st.texture_store.insert(.{ .tex = tex, .view = view });
    if (bits == c.KE_HANDLE_NONE) {
        st.device.destroy_texture_view.?(st.device, view);
        st.device.destroy_texture.?(st.device, tex);
        return .{ .bits = c.KE_HANDLE_NONE };
    }
    registerCached(st.texture_cache, key, bits);
    return .{ .bits = bits };
}

pub fn uploadCubemap(self: [*c]c.ke_render_core, key: [*c]const u8, face_size: u32, faces: ?*const anyopaque, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_texture_handle {
    if (!keyValid(key)) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "upload_cubemap requires a non-empty key", @src().file, @intCast(@src().line), null);
        return .{ .bits = c.KE_HANDLE_NONE };
    }
    const st = rc.coreOf(self);

    const cached = tryCached(st.texture_cache, key);
    if (cached != c.KE_HANDLE_NONE) return .{ .bits = cached };

    const tex = st.device.create_texture.?(st.device, &c.ke_gpu_texture_params{
        .width = face_size,
        .height = face_size,
        .depth_or_array_layers = 6,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = c.KE_GPU_TEXTURE_DIM_CUBE,
        .usage = c.KE_GPU_TEXTURE_USAGE_SAMPLED,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = faces,
        .initial_data_size = face_size * face_size * 4 * 6,
    });
    if (tex == c.KE_GPU_INVALID_HANDLE) return .{ .bits = c.KE_HANDLE_NONE };

    const view = st.device.create_texture_view.?(st.device, tex, &c.ke_gpu_texture_view_params{
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = c.KE_GPU_TEXTURE_DIM_CUBE,
        .aspect = c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 6,
    });

    const bits = st.texture_store.insert(.{ .tex = tex, .view = view });
    if (bits == c.KE_HANDLE_NONE) {
        st.device.destroy_texture_view.?(st.device, view);
        st.device.destroy_texture.?(st.device, tex);
        return .{ .bits = c.KE_HANDLE_NONE };
    }
    registerCached(st.texture_cache, key, bits);
    return .{ .bits = bits };
}

pub fn textureView(self: [*c]c.ke_render_core, h: c.ke_texture_handle) callconv(.c) c.ke_gpu_texture_view {
    const st = rc.coreOf(self);
    // A none/stale handle resolves to the built-in default (black) cubemap for
    // environment binds, else the built-in white; the binding stays valid.
    if (st.textureAt(h)) |t| return t.view;
    const fallback = if (h.bits == c.KE_HANDLE_NONE) st.default_cubemap else st.white_texture_h;
    return (st.textureAt(fallback) orelse return c.KE_GPU_INVALID_HANDLE).view;
}

pub fn samplerOf(self: [*c]c.ke_render_core) callconv(.c) c.ke_gpu_sampler {
    return rc.coreOf(self).sampler;
}

pub fn whiteTexture(self: [*c]c.ke_render_core) callconv(.c) c.ke_texture_handle {
    return rc.coreOf(self).white_texture_h;
}

// ── material ────────────────────────────────────────────────────────────────

// sRGB → linear (IEC 61966-2-1). Authored base colors are sRGB; lighting runs in
// linear space, so the factor is linearized once here (the final pass re-encodes
// to sRGB on output). Alpha is not a color channel and stays as-is.
fn srgbToLinear(cs: f32) f32 {
    return if (cs <= 0.04045) cs / 12.92 else std.math.pow(f32, (cs + 0.055) / 1.055, 2.4);
}

pub fn createMaterial(self: [*c]c.ke_render_core, key: [*c]const u8, base_color: [*c]const f32, metallic: f32, roughness: f32, albedo: c.ke_texture_handle, normal: c.ke_texture_handle, alpha_mode: c.ke_alpha_mode, alpha_cutoff: f32, ior: f32, distortion_strength: f32, shader_variant: u32, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_material_handle {
    const st = rc.coreOf(self);
    if (!keyValid(key)) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_material requires a non-empty key", @src().file, @intCast(@src().line), null);
        return .{ .bits = c.KE_HANDLE_NONE };
    }

    const cached = tryCached(st.material_cache, key);
    if (cached != c.KE_HANDLE_NONE) return .{ .bits = cached };

    // std140: float4 base_color (linearized) + float4(metallic, roughness,
    // alpha_cutoff, ior) + float4(distortion_strength, pad, pad, pad). Only MASK
    // writes a real alpha_cutoff — OPAQUE/BLEND get 0.0, which the shader's
    // `alpha < cutoff` discard never trips (alpha is never negative).
    const gpu_alpha_cutoff: f32 = if (alpha_mode == c.KE_ALPHA_MODE_MASK) alpha_cutoff else 0.0;
    const mat_data = [12]f32{
        srgbToLinear(base_color[0]), srgbToLinear(base_color[1]), srgbToLinear(base_color[2]), base_color[3],
        metallic,                    roughness,                   gpu_alpha_cutoff,            ior,
        distortion_strength,         0.0,                         0.0,                         0.0,
    };
    const ubo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .initial_data = &mat_data,
        .size = 48,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (ubo == c.KE_GPU_INVALID_HANDLE) return .{ .bits = c.KE_HANDLE_NONE };

    // Resolve none/stale albedo → built-in white, none/stale normal → built-in
    // flat (0,0,1). The material retains these resolved textures so its bind
    // group's views survive an independent release of the same texture elsewhere.
    const alb: c.ke_texture_handle = if (st.textureAt(albedo) != null) albedo else st.white_texture_h;
    const nrm: c.ke_texture_handle = if (st.textureAt(normal) != null) normal else st.default_normal;
    const alb_view = st.textureAt(alb).?.view;
    const nrm_view = st.textureAt(nrm).?.view;

    const entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = ubo, .buffer_offset = 0, .buffer_size = 48, .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = alb_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = st.sampler },
        .{ .binding = 3, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = nrm_view, .sampler = 0 },
    };
    const bg = st.device.create_bind_group.?(st.device, &c.ke_gpu_bind_group_params{
        .layout = st.material_bgl,
        .entry_count = 4,
        .entries = &entries,
    }, out_error);
    if (bg == c.KE_GPU_INVALID_HANDLE) {
        st.device.destroy_buffer.?(st.device, ubo);
        return .{ .bits = c.KE_HANDLE_NONE };
    }

    const bits = st.material_store.insert(.{
        .ubo = ubo,
        .bind_group = bg,
        .alpha_mode = alpha_mode,
        .alpha_cutoff = alpha_cutoff,
        .shader_variant = shader_variant,
        .albedo = alb,
        .normal = nrm,
    });
    if (bits == c.KE_HANDLE_NONE) {
        st.device.destroy_bind_group.?(st.device, bg);
        st.device.destroy_buffer.?(st.device, ubo);
        return .{ .bits = c.KE_HANDLE_NONE };
    }
    // Hold a reference to each sampled texture for the material's lifetime.
    _ = st.texture_cache.retain.?(st.texture_cache, alb.bits, null);
    _ = st.texture_cache.retain.?(st.texture_cache, nrm.bits, null);
    registerCached(st.material_cache, key, bits);
    return .{ .bits = bits };
}

pub fn materialAlphaMode(self: [*c]c.ke_render_core, h: c.ke_material_handle) callconv(.c) c.ke_alpha_mode {
    return rc.coreOf(self).materialAt(h).alpha_mode;
}

pub fn materialAlphaCutoff(self: [*c]c.ke_render_core, h: c.ke_material_handle) callconv(.c) f32 {
    return rc.coreOf(self).materialAt(h).alpha_cutoff;
}

pub fn materialShaderVariant(self: [*c]c.ke_render_core, h: c.ke_material_handle) callconv(.c) u32 {
    return rc.coreOf(self).materialAt(h).shader_variant;
}

pub fn materialLayout(self: [*c]c.ke_render_core) callconv(.c) c.ke_gpu_bind_group_layout {
    return rc.coreOf(self).material_bgl;
}

pub fn materialBindGroup(self: [*c]c.ke_render_core, h: c.ke_material_handle) callconv(.c) c.ke_gpu_bind_group {
    return rc.coreOf(self).materialAt(h).bind_group;
}

// ── refcount control ────────────────────────────────────────────────────────

pub fn retainMesh(self: [*c]c.ke_render_core, h: c.ke_mesh_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.mesh_cache.retain.?(st.mesh_cache, h.bits, null);
}
pub fn releaseMesh(self: [*c]c.ke_render_core, h: c.ke_mesh_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.mesh_cache.release.?(st.mesh_cache, h.bits, null);
}
pub fn retainTexture(self: [*c]c.ke_render_core, h: c.ke_texture_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.texture_cache.retain.?(st.texture_cache, h.bits, null);
}
pub fn releaseTexture(self: [*c]c.ke_render_core, h: c.ke_texture_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.texture_cache.release.?(st.texture_cache, h.bits, null);
}
pub fn retainMaterial(self: [*c]c.ke_render_core, h: c.ke_material_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.material_cache.retain.?(st.material_cache, h.bits, null);
}
pub fn releaseMaterial(self: [*c]c.ke_render_core, h: c.ke_material_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.material_cache.release.?(st.material_cache, h.bits, null);
}

// ── keyed probes ────────────────────────────────────────────────────────────

pub fn tryGetMesh(self: [*c]c.ke_render_core, key: [*c]const u8, out: [*c]c.ke_mesh_handle) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    var bits: c.ke_resource_handle = c.KE_HANDLE_NONE;
    if (!st.mesh_cache.try_get_cached.?(st.mesh_cache, key, &bits)) return 0;
    out.* = .{ .bits = bits };
    return 1;
}
pub fn tryGetTexture(self: [*c]c.ke_render_core, key: [*c]const u8, out: [*c]c.ke_texture_handle) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    var bits: c.ke_resource_handle = c.KE_HANDLE_NONE;
    if (!st.texture_cache.try_get_cached.?(st.texture_cache, key, &bits)) return 0;
    out.* = .{ .bits = bits };
    return 1;
}
pub fn tryGetMaterial(self: [*c]c.ke_render_core, key: [*c]const u8, out: [*c]c.ke_material_handle) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    var bits: c.ke_resource_handle = c.KE_HANDLE_NONE;
    if (!st.material_cache.try_get_cached.?(st.material_cache, key, &bits)) return 0;
    out.* = .{ .bits = bits };
    return 1;
}

// ── cache destroy callbacks (fired at refcount 0 and at cache teardown) ──────

pub fn destroyMeshResource(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.mesh_store.remove(handle)) |m| {
        st.device.destroy_buffer.?(st.device, m.vbo);
        st.device.destroy_buffer.?(st.device, m.ibo);
    }
}

pub fn destroyTextureResource(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.texture_store.remove(handle)) |t| {
        st.device.destroy_texture_view.?(st.device, t.view);
        st.device.destroy_texture.?(st.device, t.tex);
    }
}

pub fn destroyMaterialResource(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.material_store.remove(handle)) |m| {
        st.device.destroy_bind_group.?(st.device, m.bind_group);
        st.device.destroy_buffer.?(st.device, m.ubo);
        // Drop the references taken in createMaterial for the sampled textures.
        _ = st.texture_cache.release.?(st.texture_cache, m.albedo.bits, null);
        _ = st.texture_cache.release.?(st.texture_cache, m.normal.bits, null);
    }
}
