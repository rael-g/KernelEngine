//! Creates and looks up the meshes, textures, cubemaps and materials of the render service, and
//! destroys them when their last reference goes.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_handles = @import("abi_render_handles");
const std = @import("std");
const rc = @import("render_service.zig");
const abi_render = @import("abi_render");
const abi_resource_cache = @import("abi_resource_cache");
const abi_result = @import("abi_result");
const R = rc.R;
const log = std.log.scoped(.render_service);

/// Creation functions in this file share one order: validate the key, return the cached handle
/// on a hit, create the GPU objects, insert the slot into the store, and only then register the
/// handle and the key in the cache. A failure part-way destroys what was already made.
fn keyValid(key: [*c]const u8) bool {
    return key != null and key[0] != 0;
}

fn tryCached(cache: *abi_resource_cache.c.ke_resource_cache, key: [*c]const u8) u32 {
    var out: abi_resource_cache.c.ke_resource_handle = abi_render_handles.c.KE_HANDLE_NONE;
    if (cache.try_get_cached.?(cache, key, &out)) return out;
    return abi_render_handles.c.KE_HANDLE_NONE;
}

/// Called last in a creation, once the slot is in its store, so a key the cache finds always
/// names a stored slot.
fn registerCached(cache: *abi_resource_cache.c.ke_resource_cache, key: [*c]const u8, bits: u32) void {
    _ = cache.register_resource.?(cache, bits);
    _ = cache.cache_insert.?(cache, key, bits);
}

/// Creates a vertex buffer and an index buffer for the key and stores them as one mesh. A key the
/// mesh cache already holds writes its handle without creating anything. An empty or null key
/// fails as an invalid argument. A buffer the device cannot create fails with the device's code,
/// after destroying the buffer made before it. A full store fails as out of memory, after
/// destroying both buffers.
pub fn uploadMesh(self: [*c]abi_render.c.ke_render_service, key: [*c]const u8, vertices: ?*const anyopaque, vertices_size: usize, indices: [*c]const u16, index_count: u32, out_mesh: [*c]abi_render_handles.c.ke_mesh_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_mesh orelse return R.code(error.InvalidArgument);
    out.* = .{ .bits = abi_render_handles.c.KE_HANDLE_NONE };
    if (self == null or !keyValid(key)) return R.code(error.InvalidArgument);
    out.* = .{ .bits = mesh(rc.coreOf(self), key, vertices, vertices_size, indices, index_count) catch |err| return R.code(err) };
    return R.ok;
}

fn mesh(st: *rc.CoreState, key: [*c]const u8, vertices: ?*const anyopaque, vertices_size: usize, indices: [*c]const u16, index_count: u32) R.Error!u32 {
    const cached = tryCached(st.mesh_cache, key);
    if (cached != abi_render_handles.c.KE_HANDLE_NONE) return cached;

    var vbo: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    try R.check(st.device.create_buffer.?(st.device, &abi_render_gpu.c.ke_gpu_buffer_params{
        .label = "mesh.vertices",
        .initial_data = vertices,
        .size = vertices_size,
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_VERTEX | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &vbo));
    errdefer st.device.destroy_buffer.?(st.device, vbo);

    var ibo: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    try R.check(st.device.create_buffer.?(st.device, &abi_render_gpu.c.ke_gpu_buffer_params{
        .label = "mesh.indices",
        .initial_data = @ptrCast(indices),
        .size = index_count * @sizeOf(u16),
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_INDEX | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &ibo));
    errdefer st.device.destroy_buffer.?(st.device, ibo);

    const bits = st.mesh_store.insert(.{ .vbo = vbo, .ibo = ibo, .index_count = index_count });
    if (bits == abi_render_handles.c.KE_HANDLE_NONE) return error.OutOfMemory;
    registerCached(st.mesh_cache, key, bits);
    return bits;
}

/// Writes the buffers and the index count of the mesh through the out-parameters. Returns zero and
/// writes nothing when the handle no longer names a stored mesh.
pub fn meshBuffers(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_mesh_handle, out_vbo: [*c]abi_asset_resolver.c.ke_gpu_buffer, out_ibo: [*c]abi_asset_resolver.c.ke_gpu_buffer, out_index_count: [*c]u32) callconv(.c) bool {
    const st = rc.coreOf(self);
    const m = st.meshAt(h) orelse return false;
    out_vbo.* = m.vbo;
    out_ibo.* = m.ibo;
    out_index_count.* = m.index_count;
    return true;
}

/// Sets the color a color attachment is cleared to when its resource carries no clear value of
/// its own.
pub fn setClearColor(self: [*c]abi_render.c.ke_render_service, r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    rc.coreOf(self).clear_color = .{ r, g, b, a };
}

/// Creates a sampled RGBA 2D texture and its view for the key, from the pixels given. A cache hit
/// writes the cached handle. An empty or null key fails as an invalid argument. A texture or view
/// the device cannot create fails with the device's code, and a full store as out of memory,
/// destroying what was made first.
pub fn uploadTexture(self: [*c]abi_render.c.ke_render_service, key: [*c]const u8, width: u32, height: u32, rgba: ?*const anyopaque, out_texture: [*c]abi_render_handles.c.ke_texture_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_texture orelse return R.code(error.InvalidArgument);
    out.* = .{ .bits = abi_render_handles.c.KE_HANDLE_NONE };
    if (self == null or !keyValid(key)) return R.code(error.InvalidArgument);
    out.* = .{ .bits = texture(rc.coreOf(self), key, width, height, 1, abi_render_gpu.c.KE_GPU_TEXTURE_DIM_2D, rgba) catch |err| return R.code(err) };
    return R.ok;
}

/// Creates a sampled RGBA cube texture and its view for the key, from six faces of the size given,
/// and stores it in `texture_store` beside the 2D textures, so a cubemap handle is a texture
/// handle. The failures are those of `uploadTexture`.
pub fn uploadCubemap(self: [*c]abi_render.c.ke_render_service, key: [*c]const u8, face_size: u32, faces: ?*const anyopaque, out_cubemap: [*c]abi_render_handles.c.ke_texture_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_cubemap orelse return R.code(error.InvalidArgument);
    out.* = .{ .bits = abi_render_handles.c.KE_HANDLE_NONE };
    if (self == null or !keyValid(key)) return R.code(error.InvalidArgument);
    out.* = .{ .bits = texture(rc.coreOf(self), key, face_size, face_size, 6, abi_render_gpu.c.KE_GPU_TEXTURE_DIM_CUBE, faces) catch |err| return R.code(err) };
    return R.ok;
}

fn texture(st: *rc.CoreState, key: [*c]const u8, width: u32, height: u32, layers: u8, dimension: abi_render_gpu.c.ke_gpu_texture_dimension, pixels: ?*const anyopaque) R.Error!u32 {
    const cached = tryCached(st.texture_cache, key);
    if (cached != abi_render_handles.c.KE_HANDLE_NONE) return cached;

    var tex: abi_asset_resolver.c.ke_gpu_texture = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    try R.check(st.device.create_texture.?(st.device, &abi_render_gpu.c.ke_gpu_texture_params{
        .label = key,
        .width = width,
        .height = height,
        .depth_or_array_layers = layers,
        .format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = dimension,
        .usage = abi_render_gpu.c.KE_GPU_TEXTURE_USAGE_SAMPLED,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = pixels,
        .initial_data_size = width * height * 4 * layers,
    }, &tex));
    errdefer st.device.destroy_texture.?(st.device, tex);

    var view: abi_asset_resolver.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    try R.check(st.device.create_texture_view.?(st.device, tex, &abi_render_gpu.c.ke_gpu_texture_view_params{
        .label = key,
        .format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = dimension,
        .aspect = abi_render_gpu.c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = layers,
    }, &view));
    errdefer st.device.destroy_texture_view.?(st.device, view);

    const bits = st.texture_store.insert(.{ .tex = tex, .view = view });
    if (bits == abi_render_handles.c.KE_HANDLE_NONE) return error.OutOfMemory;
    registerCached(st.texture_cache, key, bits);
    return bits;
}

/// Returns the view of the texture, or a stand-in when the handle names no stored texture: the
/// view of `default_cubemap` for the none handle, the view of `white_texture_h` for any other
/// handle. Returns the invalid view when the stand-in is itself missing.
pub fn textureView(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_texture_handle) callconv(.c) abi_asset_resolver.c.ke_gpu_texture_view {
    const st = rc.coreOf(self);
    if (st.textureAt(h)) |t| return t.view;
    const fallback = if (h.bits == abi_render_handles.c.KE_HANDLE_NONE) st.default_cubemap else st.white_texture_h;
    return (st.textureAt(fallback) orelse return abi_render_gpu.c.KE_GPU_INVALID_HANDLE).view;
}

/// Returns the handle of the 1x1 white texture the service created at start.
pub fn whiteTexture(self: [*c]abi_render.c.ke_render_service) callconv(.c) abi_render_handles.c.ke_texture_handle {
    return rc.coreOf(self).white_texture_h;
}

fn srgbToLinear(cs: f32) f32 {
    return if (cs <= 0.04045) cs / 12.92 else std.math.pow(f32, (cs + 0.055) / 1.055, 2.4);
}

/// Hands the material's data to the binder. The base color is converted from sRGB to linear. The
/// alpha cutoff reaches the binder only in the mask mode, while the stored record keeps the value
/// as given. A shader name is copied into the record's fixed buffer: an empty name takes the
/// default shader. An albedo or normal that names no stored texture is replaced by
/// `white_texture_h` or `default_normal`, and the texture actually used is retained. A cache hit
/// writes the cached handle. An empty or null key, or a shader name that does not fit the buffer,
/// fails as an invalid argument. A material the binder cannot keep fails with the binder's code,
/// and a full store as out of memory, giving the binder's back.
pub fn createMaterial(self: [*c]abi_render.c.ke_render_service, key: [*c]const u8, base_color: [*c]const f32, metallic: f32, roughness: f32, albedo: abi_render_handles.c.ke_texture_handle, normal: abi_render_handles.c.ke_texture_handle, alpha_mode: abi_render_handles.c.ke_alpha_mode, alpha_cutoff: f32, ior: f32, distortion_strength: f32, shader: [*c]const u8, out_material: [*c]abi_render_handles.c.ke_material_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_material orelse return R.code(error.InvalidArgument);
    out.* = .{ .bits = abi_render_handles.c.KE_HANDLE_NONE };
    if (self == null or !keyValid(key) or base_color == null) return R.code(error.InvalidArgument);
    const st = rc.coreOf(self);

    const shader_span: []const u8 = if (shader != null and shader[0] != 0) std.mem.span(shader) else rc.DEFAULT_MATERIAL_SHADER;
    if (shader_span.len >= rc.MAX_SHADER_NAME) {
        log.warn("create_material: the shader name of {s} is too long", .{std.mem.span(key)});
        return R.code(error.InvalidArgument);
    }
    var shader_buf = std.mem.zeroes([rc.MAX_SHADER_NAME]u8);
    @memcpy(shader_buf[0..shader_span.len], shader_span);

    const cached = tryCached(st.material_cache, key);
    if (cached != abi_render_handles.c.KE_HANDLE_NONE) {
        out.* = .{ .bits = cached };
        return R.ok;
    }

    const alb: abi_render_handles.c.ke_texture_handle = if (st.textureAt(albedo) != null) albedo else st.white_texture_h;
    const nrm: abi_render_handles.c.ke_texture_handle = if (st.textureAt(normal) != null) normal else st.default_normal;
    const data = abi_render_gpu.c.ke_render_material_data{
        .base_color = .{ srgbToLinear(base_color[0]), srgbToLinear(base_color[1]), srgbToLinear(base_color[2]), base_color[3] },
        .metallic = metallic,
        .roughness = roughness,
        .alpha_cutoff = if (alpha_mode == abi_render_handles.c.KE_ALPHA_MODE_MASK) alpha_cutoff else 0.0,
        .ior = ior,
        .distortion_strength = distortion_strength,
        .albedo = st.textureAt(alb).?.view,
        .normal_map = st.textureAt(nrm).?.view,
    };
    var binding: abi_asset_resolver.c.ke_render_material_binding = abi_render_gpu.c.KE_RENDER_BINDING_INVALID;
    const made = st.binder.create_material.?(st.binder, &data, &binding);
    if (made != R.ok) return made;

    const bits = st.material_store.insert(.{
        .binding = binding,
        .alpha_mode = alpha_mode,
        .alpha_cutoff = alpha_cutoff,
        .shader = shader_buf,
        .albedo = alb,
        .normal = nrm,
    });
    if (bits == abi_render_handles.c.KE_HANDLE_NONE) {
        st.binder.destroy_material.?(st.binder, binding);
        return R.code(error.OutOfMemory);
    }
    _ = st.texture_cache.retain.?(st.texture_cache, alb.bits);
    _ = st.texture_cache.retain.?(st.texture_cache, nrm.bits);
    registerCached(st.material_cache, key, bits);
    out.* = .{ .bits = bits };
    return R.ok;
}

/// Returns the alpha mode of the material; a handle that names no material answers with the
/// default white material's.
pub fn materialAlphaMode(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_material_handle) callconv(.c) abi_render_handles.c.ke_alpha_mode {
    return rc.coreOf(self).materialAt(h).alpha_mode;
}

/// Returns the alpha cutoff as given at creation; a handle that names no material answers with
/// the default white material's.
pub fn materialAlphaCutoff(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_material_handle) callconv(.c) f32 {
    return rc.coreOf(self).materialAt(h).alpha_cutoff;
}

/// The returned pointer points into the material's record, so it is valid until the material is
/// destroyed.
pub fn materialShader(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_material_handle) callconv(.c) [*c]const u8 {
    return @ptrCast(&rc.coreOf(self).materialAt(h).shader);
}

/// Returns what the binder holds for the material; a handle that names no material answers with
/// the default white material's.
pub fn materialBinding(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_material_handle) callconv(.c) abi_asset_resolver.c.ke_render_material_binding {
    return rc.coreOf(self).materialAt(h).binding;
}

/// Adds a reference to the mesh in the mesh cache.
pub fn retainMesh(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_mesh_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.mesh_cache.retain.?(st.mesh_cache, h.bits);
}
/// Drops a reference; the last one runs `destroyMeshResource`.
pub fn releaseMesh(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_mesh_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.mesh_cache.release.?(st.mesh_cache, h.bits);
}
/// Adds a reference to the texture in the texture cache.
pub fn retainTexture(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_texture_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.texture_cache.retain.?(st.texture_cache, h.bits);
}
/// Drops a reference; the last one runs `destroyTextureResource`.
pub fn releaseTexture(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_texture_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.texture_cache.release.?(st.texture_cache, h.bits);
}
/// Adds a reference to the material in the material cache.
pub fn retainMaterial(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_material_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.material_cache.retain.?(st.material_cache, h.bits);
}
/// Drops a reference; the last one runs `destroyMaterialResource`.
pub fn releaseMaterial(self: [*c]abi_render.c.ke_render_service, h: abi_render_handles.c.ke_material_handle) callconv(.c) void {
    const st = rc.coreOf(self);
    _ = st.material_cache.release.?(st.material_cache, h.bits);
}

/// Looks the key up in the mesh cache without creating anything. Returns zero and leaves the
/// out-parameter alone on a miss.
pub fn tryGetMesh(self: [*c]abi_render.c.ke_render_service, key: [*c]const u8, out: [*c]abi_render_handles.c.ke_mesh_handle) callconv(.c) bool {
    const st = rc.coreOf(self);
    var bits: abi_resource_cache.c.ke_resource_handle = abi_render_handles.c.KE_HANDLE_NONE;
    if (!st.mesh_cache.try_get_cached.?(st.mesh_cache, key, &bits)) return false;
    out.* = .{ .bits = bits };
    return true;
}
/// Looks the key up in the texture cache without creating anything. Returns zero and leaves the
/// out-parameter alone on a miss.
pub fn tryGetTexture(self: [*c]abi_render.c.ke_render_service, key: [*c]const u8, out: [*c]abi_render_handles.c.ke_texture_handle) callconv(.c) bool {
    const st = rc.coreOf(self);
    var bits: abi_resource_cache.c.ke_resource_handle = abi_render_handles.c.KE_HANDLE_NONE;
    if (!st.texture_cache.try_get_cached.?(st.texture_cache, key, &bits)) return false;
    out.* = .{ .bits = bits };
    return true;
}
/// Looks the key up in the material cache without creating anything. Returns zero and leaves
/// the out-parameter alone on a miss.
pub fn tryGetMaterial(self: [*c]abi_render.c.ke_render_service, key: [*c]const u8, out: [*c]abi_render_handles.c.ke_material_handle) callconv(.c) bool {
    const st = rc.coreOf(self);
    var bits: abi_resource_cache.c.ke_resource_handle = abi_render_handles.c.KE_HANDLE_NONE;
    if (!st.material_cache.try_get_cached.?(st.material_cache, key, &bits)) return false;
    out.* = .{ .bits = bits };
    return true;
}

/// Runs from the mesh cache when the last reference goes. Removes the slot and destroys both
/// buffers; a handle already removed does nothing.
pub fn destroyMeshResource(handle: abi_resource_cache.c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.mesh_store.remove(handle)) |m| {
        st.device.destroy_buffer.?(st.device, m.vbo);
        st.device.destroy_buffer.?(st.device, m.ibo);
    }
}

/// Runs from the texture cache when the last reference goes. Removes the slot and destroys the
/// view and the texture; a handle already removed does nothing.
pub fn destroyTextureResource(handle: abi_resource_cache.c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.texture_store.remove(handle)) |t| {
        st.device.destroy_texture_view.?(st.device, t.view);
        st.device.destroy_texture.?(st.device, t.tex);
    }
}

/// Runs from the material cache's release when the last reference goes. Besides the slot and the
/// GPU objects, it releases the two textures the material retained at creation.
pub fn destroyMaterialResource(handle: abi_resource_cache.c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const st: *rc.CoreState = @alignCast(@ptrCast(ctx));
    if (st.material_store.remove(handle)) |m| {
        st.binder.destroy_material.?(st.binder, m.binding);
        _ = st.texture_cache.release.?(st.texture_cache, m.albedo.bits);
        _ = st.texture_cache.release.?(st.texture_cache, m.normal.bits);
    }
}
