//! Meshes, textures, cubemaps and materials, each kept in a store of `CoreState` addressed by a
//! handle and in a resource cache addressed by a caller-chosen key.
//!
//! `uploadMesh`, `uploadTexture`, `uploadCubemap` and `createMaterial` share one order: validate
//! the key, return the cached handle on a hit, create the GPU objects, insert the slot into the
//! store, and only then register the handle and the key in the cache. A failure part-way destroys
//! what was already made, so a cached key always names a stored slot with live objects. When the
//! last reference goes, the cache runs the matching destroy function, `destroyMeshResource`,
//! `destroyTextureResource` or `destroyMaterialResource`, which removes the slot and its objects.
//!
//! A material keeps its two textures alive: `createMaterial` retains them and
//! `destroyMaterialResource` releases them. The rest of the file is lookups and accessors over the
//! stores, `tryGetMesh` among them.

const std = @import("std");
const rc = @import("render_service.zig");
const c = rc.c;

fn keyValid(key: [*c]const u8) bool {
    return key != null and key[0] != 0;
}

fn tryCached(cache: *c.ke_resource_cache, key: [*c]const u8) u32 {
    var out: c.ke_resource_handle = c.KE_HANDLE_NONE;
    if (cache.try_get_cached.?(cache, key, &out)) return out;
    return c.KE_HANDLE_NONE;
}

/// Called last in a creation, once the slot is in its store. The cache learns the handle and then
/// the key, so a key the cache finds always names a stored slot.
fn registerCached(cache: *c.ke_resource_cache, key: [*c]const u8, bits: u32) void {
    _ = cache.register_resource.?(cache, bits, null);
    _ = cache.cache_insert.?(cache, key, bits, null);
}

/// Creates a vertex buffer and an index buffer for the key and stores them as one mesh. A key the
/// mesh cache already holds returns its handle without creating anything. An empty or null key
/// fills the error with an invalid-argument error. A buffer the device cannot create returns the
/// none handle with the device's error, after destroying the buffer made before it. A full store
/// returns the none handle without an error, after destroying both buffers.
pub fn uploadMesh(self: [*c]c.ke_render_service, key: [*c]const u8, vertices: ?*const anyopaque, vertices_size: usize, indices: [*c]const u16, index_count: u32, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_mesh_handle {
    const st = rc.coreOf(self);
    if (!keyValid(key)) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "upload_mesh requires a non-empty key", @src().file, @intCast(@src().line), null);
        return .{ .bits = c.KE_HANDLE_NONE };
    }

    const cached = tryCached(st.mesh_cache, key);
    if (cached != c.KE_HANDLE_NONE) return .{ .bits = cached };

    const vbo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .label = "mesh.vertices",
        .initial_data = vertices,
        .size = vertices_size,
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (vbo == c.KE_GPU_INVALID_HANDLE) return .{ .bits = c.KE_HANDLE_NONE };

    const ibo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .label = "mesh.indices",
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

/// Writes the buffers and the index count of the mesh through the out-parameters. Returns zero and
/// writes nothing when the handle no longer names a stored mesh.
pub fn meshBuffers(self: [*c]c.ke_render_service, h: c.ke_mesh_handle, out_vbo: [*c]c.ke_gpu_buffer, out_ibo: [*c]c.ke_gpu_buffer, out_index_count: [*c]u32) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    const m = st.meshAt(h) orelse return 0;
    out_vbo.* = m.vbo;
    out_ibo.* = m.ibo;
    out_index_count.* = m.index_count;
    return 1;
}

pub fn setClearColor(self: [*c]c.ke_render_service, r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    rc.coreOf(self).clear_color = .{ r, g, b, a };
}

/// Creates a sampled RGBA 2D texture and its view for the key, from the pixels given. A cache hit
/// returns the cached handle. An empty or null key fills the error with an invalid-argument
/// error. A texture the device cannot create, or a full store, returns the none handle; the store
/// case destroys the view and the texture first.
pub fn uploadTexture(self: [*c]c.ke_render_service, key: [*c]const u8, width: u32, height: u32, rgba: ?*const anyopaque, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_texture_handle {
    const st = rc.coreOf(self);
    if (!keyValid(key)) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "upload_texture requires a non-empty key", @src().file, @intCast(@src().line), null);
        return .{ .bits = c.KE_HANDLE_NONE };
    }

    const cached = tryCached(st.texture_cache, key);
    if (cached != c.KE_HANDLE_NONE) return .{ .bits = cached };

    const tex = st.device.create_texture.?(st.device, &c.ke_gpu_texture_params{
        .label = key,
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
        .label = key,
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

/// Creates a sampled RGBA cube texture and its view for the key, from six faces of the size given,
/// and stores it in `texture_store` beside the 2D textures, so a cubemap handle is a texture
/// handle. The failures are those of `uploadTexture`.
pub fn uploadCubemap(self: [*c]c.ke_render_service, key: [*c]const u8, face_size: u32, faces: ?*const anyopaque, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_texture_handle {
    if (!keyValid(key)) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "upload_cubemap requires a non-empty key", @src().file, @intCast(@src().line), null);
        return .{ .bits = c.KE_HANDLE_NONE };
    }
    const st = rc.coreOf(self);

    const cached = tryCached(st.texture_cache, key);
    if (cached != c.KE_HANDLE_NONE) return .{ .bits = cached };

    const tex = st.device.create_texture.?(st.device, &c.ke_gpu_texture_params{
        .label = key,
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
        .label = key,
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

/// Returns the view of the texture, or a stand-in when the handle names no stored texture: the
/// view of `default_cubemap` for the none handle, the view of `white_texture_h` for any other
/// handle. Returns the invalid view when the stand-in is itself missing.
pub fn textureView(self: [*c]c.ke_render_service, h: c.ke_texture_handle) callconv(.c) c.ke_gpu_texture_view {
    const st = rc.coreOf(self);
    if (st.textureAt(h)) |t| return t.view;
    const fallback = if (h.bits == c.KE_HANDLE_NONE) st.default_cubemap else st.white_texture_h;
    return (st.textureAt(fallback) orelse return c.KE_GPU_INVALID_HANDLE).view;
}

pub fn samplerOf(self: [*c]c.ke_render_service) callconv(.c) c.ke_gpu_sampler {
    return rc.coreOf(self).sampler;
}

pub fn whiteTexture(self: [*c]c.ke_render_service) callconv(.c) c.ke_texture_handle {
    return rc.coreOf(self).white_texture_h;
}

fn srgbToLinear(cs: f32) f32 {
    return if (cs <= 0.04045) cs / 12.92 else std.math.pow(f32, (cs + 0.055) / 1.055, 2.4);
}

/// Packs the uniform from the arguments and builds the bind group against the material layout. The
/// base color is converted from sRGB to linear. The alpha cutoff reaches the uniform only in the
/// mask mode, while the stored record keeps the value as given. A shader name is copied into the
/// record's fixed buffer: an empty name takes the default shader. An albedo or normal that names
/// no stored texture is replaced by `white_texture_h` or `default_normal`, and the texture
/// actually used is retained. A cache hit returns the cached handle. An empty or null key, or a
/// shader name that does not fit the buffer, fills the error with an invalid-argument error and
/// returns the none handle. A buffer or bind group the device cannot create returns the none
/// handle with the device's error, and a full store returns it without one; both destroy what was
/// already made.
pub fn createMaterial(self: [*c]c.ke_render_service, key: [*c]const u8, base_color: [*c]const f32, metallic: f32, roughness: f32, albedo: c.ke_texture_handle, normal: c.ke_texture_handle, alpha_mode: c.ke_alpha_mode, alpha_cutoff: f32, ior: f32, distortion_strength: f32, shader: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_material_handle {
    const st = rc.coreOf(self);
    if (!keyValid(key)) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_material requires a non-empty key", @src().file, @intCast(@src().line), null);
        return .{ .bits = c.KE_HANDLE_NONE };
    }

    const shader_span: []const u8 = if (shader != null and shader[0] != 0) std.mem.span(shader) else rc.DEFAULT_MATERIAL_SHADER;
    if (shader_span.len >= rc.MAX_SHADER_NAME) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_material: shader name too long", @src().file, @intCast(@src().line), null);
        return .{ .bits = c.KE_HANDLE_NONE };
    }
    var shader_buf = std.mem.zeroes([rc.MAX_SHADER_NAME]u8);
    @memcpy(shader_buf[0..shader_span.len], shader_span);

    const cached = tryCached(st.material_cache, key);
    if (cached != c.KE_HANDLE_NONE) return .{ .bits = cached };

    const gpu_alpha_cutoff: f32 = if (alpha_mode == c.KE_ALPHA_MODE_MASK) alpha_cutoff else 0.0;
    const mat_data = [12]f32{
        srgbToLinear(base_color[0]), srgbToLinear(base_color[1]), srgbToLinear(base_color[2]), base_color[3],
        metallic,                    roughness,                   gpu_alpha_cutoff,            ior,
        distortion_strength,         0.0,                         0.0,                         0.0,
    };
    const ubo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .label = "material.uniform",
        .initial_data = &mat_data,
        .size = 48,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (ubo == c.KE_GPU_INVALID_HANDLE) return .{ .bits = c.KE_HANDLE_NONE };

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
        .label = "material.bind_group",
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
        .shader = shader_buf,
        .albedo = alb,
        .normal = nrm,
    });
    if (bits == c.KE_HANDLE_NONE) {
        st.device.destroy_bind_group.?(st.device, bg);
        st.device.destroy_buffer.?(st.device, ubo);
        return .{ .bits = c.KE_HANDLE_NONE };
    }
    _ = st.texture_cache.retain.?(st.texture_cache, alb.bits, null);
    _ = st.texture_cache.retain.?(st.texture_cache, nrm.bits, null);
    registerCached(st.material_cache, key, bits);
    return .{ .bits = bits };
}

pub fn materialAlphaMode(self: [*c]c.ke_render_service, h: c.ke_material_handle) callconv(.c) c.ke_alpha_mode {
    return rc.coreOf(self).materialAt(h).alpha_mode;
}

pub fn materialAlphaCutoff(self: [*c]c.ke_render_service, h: c.ke_material_handle) callconv(.c) f32 {
    return rc.coreOf(self).materialAt(h).alpha_cutoff;
}

/// The returned pointer points into the material's record, so it is valid until the material is
/// destroyed.
pub fn materialShader(self: [*c]c.ke_render_service, h: c.ke_material_handle) callconv(.c) [*c]const u8 {
    return @ptrCast(&rc.coreOf(self).materialAt(h).shader);
}

pub fn materialLayout(self: [*c]c.ke_render_service) callconv(.c) c.ke_gpu_bind_group_layout {
    return rc.coreOf(self).material_bgl;
}

pub fn materialBindGroup(self: [*c]c.ke_render_service, h: c.ke_material_handle) callconv(.c) c.ke_gpu_bind_group {
    return rc.coreOf(self).materialAt(h).bind_group;
}

pub fn retainMesh(self: [*c]c.ke_render_service, h: c.ke_mesh_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.mesh_cache.retain.?(st.mesh_cache, h.bits, null);
}
pub fn releaseMesh(self: [*c]c.ke_render_service, h: c.ke_mesh_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.mesh_cache.release.?(st.mesh_cache, h.bits, null);
}
pub fn retainTexture(self: [*c]c.ke_render_service, h: c.ke_texture_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.texture_cache.retain.?(st.texture_cache, h.bits, null);
}
pub fn releaseTexture(self: [*c]c.ke_render_service, h: c.ke_texture_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.texture_cache.release.?(st.texture_cache, h.bits, null);
}
pub fn retainMaterial(self: [*c]c.ke_render_service, h: c.ke_material_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.material_cache.retain.?(st.material_cache, h.bits, null);
}
pub fn releaseMaterial(self: [*c]c.ke_render_service, h: c.ke_material_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.material_cache.release.?(st.material_cache, h.bits, null);
}

/// Looks the key up in the mesh cache without creating anything. Returns zero and leaves the
/// out-parameter alone on a miss.
pub fn tryGetMesh(self: [*c]c.ke_render_service, key: [*c]const u8, out: [*c]c.ke_mesh_handle) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    var bits: c.ke_resource_handle = c.KE_HANDLE_NONE;
    if (!st.mesh_cache.try_get_cached.?(st.mesh_cache, key, &bits)) return 0;
    out.* = .{ .bits = bits };
    return 1;
}
pub fn tryGetTexture(self: [*c]c.ke_render_service, key: [*c]const u8, out: [*c]c.ke_texture_handle) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    var bits: c.ke_resource_handle = c.KE_HANDLE_NONE;
    if (!st.texture_cache.try_get_cached.?(st.texture_cache, key, &bits)) return 0;
    out.* = .{ .bits = bits };
    return 1;
}
pub fn tryGetMaterial(self: [*c]c.ke_render_service, key: [*c]const u8, out: [*c]c.ke_material_handle) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    var bits: c.ke_resource_handle = c.KE_HANDLE_NONE;
    if (!st.material_cache.try_get_cached.?(st.material_cache, key, &bits)) return 0;
    out.* = .{ .bits = bits };
    return 1;
}

/// Runs from the mesh cache when the last reference goes. Removes the slot and destroys both
/// buffers; a handle already removed does nothing.
pub fn destroyMeshResource(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.mesh_store.remove(handle)) |m| {
        st.device.destroy_buffer.?(st.device, m.vbo);
        st.device.destroy_buffer.?(st.device, m.ibo);
    }
}

/// Runs from the texture cache when the last reference goes. Removes the slot and destroys the
/// view and the texture; a handle already removed does nothing.
pub fn destroyTextureResource(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.texture_store.remove(handle)) |t| {
        st.device.destroy_texture_view.?(st.device, t.view);
        st.device.destroy_texture.?(st.device, t.tex);
    }
}

/// Runs from the material cache's release when the last reference goes. Besides the slot and the
/// GPU objects, it releases the two textures the material retained at creation.
pub fn destroyMaterialResource(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.material_store.remove(handle)) |m| {
        st.device.destroy_bind_group.?(st.device, m.bind_group);
        st.device.destroy_buffer.?(st.device, m.ubo);
        _ = st.texture_cache.release.?(st.texture_cache, m.albedo.bits, null);
        _ = st.texture_cache.release.?(st.texture_cache, m.normal.bits, null);
    }
}
