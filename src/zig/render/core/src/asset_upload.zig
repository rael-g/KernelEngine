const std = @import("std");
const rc = @import("render_core.zig");
const c = rc.c;

// Mesh/texture/material upload + the material bind-group system (set 1). This
// is the asset-ingestion surface a game calls once per unique mesh/texture/
// material at load time — distinct from the per-frame deferred-upload path
// (frame_lifecycle.zig's uploadBuffer), which every pass calls every frame.

pub fn uploadMesh(self: [*c]c.ke_render_core, vertices: ?*const anyopaque, vertices_size: usize,
              indices: [*c]const u16, index_count: u32, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_mesh_handle {
    const st = rc.coreOf(self);
    if (st.mesh_count >= rc.MAX_MESHES) return .{ .idx = c.KE_HANDLE_NONE };

    const vbo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .initial_data = vertices,
        .size = vertices_size,
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (vbo == c.KE_GPU_INVALID_HANDLE) return .{ .idx = c.KE_HANDLE_NONE };

    const ibo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .initial_data = @ptrCast(indices),
        .size = index_count * @sizeOf(u16),
        .usage = c.KE_GPU_BUFFER_USAGE_INDEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (ibo == c.KE_GPU_INVALID_HANDLE) {
        st.device.destroy_buffer.?(st.device, vbo);
        return .{ .idx = c.KE_HANDLE_NONE };
    }

    const idx = st.mesh_count;
    st.meshes[idx] = .{ .vbo = vbo, .ibo = ibo, .index_count = index_count };
    st.mesh_count += 1;
    return .{ .idx = idx };
}

pub fn meshBuffers(self: [*c]c.ke_render_core, h: c.ke_mesh_handle, out_vbo: [*c]c.ke_gpu_buffer,
               out_ibo: [*c]c.ke_gpu_buffer, out_index_count: [*c]u32) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    const m = st.meshAt(h.idx) orelse return 0;
    out_vbo.* = m.vbo;
    out_ibo.* = m.ibo;
    out_index_count.* = m.index_count;
    return 1;
}

pub fn setClearColor(self: [*c]c.ke_render_core, r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    rc.coreOf(self).clear_color = .{ r, g, b, a };
}

pub fn uploadTexture(self: [*c]c.ke_render_core, width: u32, height: u32,
                 rgba: ?*const anyopaque, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_texture_handle {
    _ = out_error;
    const st = rc.coreOf(self);
    if (st.texture_count >= rc.MAX_TEXTURES) return .{ .idx = c.KE_HANDLE_NONE };

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
    if (tex == c.KE_GPU_INVALID_HANDLE) return .{ .idx = c.KE_HANDLE_NONE };

    const view = st.device.create_texture_view.?(st.device, tex, &c.ke_gpu_texture_view_params{
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .aspect = c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    });

    const idx = st.texture_count;
    st.textures[idx] = .{ .tex = tex, .view = view };
    st.texture_count += 1;
    return .{ .idx = idx };
}

// sRGB → linear (IEC 61966-2-1). Authored base colors are sRGB; lighting runs in
// linear space, so the factor is linearized once here (the final pass re-encodes
// to sRGB on output). Alpha is not a color channel and stays as-is.
fn srgbToLinear(cs: f32) f32 {
    return if (cs <= 0.04045) cs / 12.92 else std.math.pow(f32, (cs + 0.055) / 1.055, 2.4);
}

pub fn createMaterial(self: [*c]c.ke_render_core, base_color: [*c]const f32,
                  metallic: f32, roughness: f32, albedo: c.ke_texture_handle,
                  normal: c.ke_texture_handle, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_material_handle {
    const st = rc.coreOf(self);
    if (st.material_count >= rc.MAX_MATERIALS) return .{ .idx = c.KE_HANDLE_NONE };

    // std140: float4 base_color (linearized) + (metallic, roughness) packed next.
    const mat_data = [8]f32{
        srgbToLinear(base_color[0]), srgbToLinear(base_color[1]), srgbToLinear(base_color[2]), base_color[3],
        metallic,                    roughness,                   0.0,                         0.0,
    };
    const ubo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .initial_data = &mat_data,
        .size = 32,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (ubo == c.KE_GPU_INVALID_HANDLE) return .{ .idx = c.KE_HANDLE_NONE };

    // Unknown / none albedo resolves to the built-in white texture (index 0);
    // none normal resolves to the built-in flat (0,0,1) normal map.
    const alb_idx = if (albedo.idx == c.KE_HANDLE_NONE) 0 else albedo.idx;
    const alb_view = (st.textureAt(alb_idx) orelse &st.textures[0]).view;
    const nrm_idx = if (normal.idx == c.KE_HANDLE_NONE) st.default_normal.idx else normal.idx;
    const nrm_view = (st.textureAt(nrm_idx) orelse &st.textures[st.default_normal.idx]).view;

    const entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = ubo, .buffer_offset = 0, .buffer_size = 32, .texture_view = 0, .sampler = 0 },
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
        return .{ .idx = c.KE_HANDLE_NONE };
    }

    const idx = st.material_count;
    st.materials[idx] = .{ .ubo = ubo, .bind_group = bg };
    st.material_count += 1;
    return .{ .idx = idx };
}

pub fn materialLayout(self: [*c]c.ke_render_core) callconv(.c) c.ke_gpu_bind_group_layout {
    return rc.coreOf(self).material_bgl;
}

pub fn materialBindGroup(self: [*c]c.ke_render_core, h: c.ke_material_handle) callconv(.c) c.ke_gpu_bind_group {
    return rc.coreOf(self).materialAt(h.idx).bind_group;
}

pub fn uploadCubemap(self: [*c]c.ke_render_core, face_size: u32, faces: ?*const anyopaque,
                 out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_texture_handle {
    _ = out_error;
    const st = rc.coreOf(self);
    if (st.texture_count >= rc.MAX_TEXTURES) return .{ .idx = c.KE_HANDLE_NONE };

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
    if (tex == c.KE_GPU_INVALID_HANDLE) return .{ .idx = c.KE_HANDLE_NONE };

    const view = st.device.create_texture_view.?(st.device, tex, &c.ke_gpu_texture_view_params{
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = c.KE_GPU_TEXTURE_DIM_CUBE,
        .aspect = c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 6,
    });

    const idx = st.texture_count;
    st.textures[idx] = .{ .tex = tex, .view = view };
    st.texture_count += 1;
    return .{ .idx = idx };
}

pub fn textureView(self: [*c]c.ke_render_core, h: c.ke_texture_handle) callconv(.c) c.ke_gpu_texture_view {
    const st = rc.coreOf(self);
    // texture_view is used to bind the environment cubemap; an unset/none handle
    // resolves to the built-in default (black) cubemap so the binding stays valid.
    const idx = if (h.idx == c.KE_HANDLE_NONE) st.default_cubemap.idx else h.idx;
    return (st.textureAt(idx) orelse &st.textures[st.default_cubemap.idx]).view;
}

pub fn samplerOf(self: [*c]c.ke_render_core) callconv(.c) c.ke_gpu_sampler {
    return rc.coreOf(self).sampler;
}
