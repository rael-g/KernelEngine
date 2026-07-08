const std = @import("std");
const zm = @import("zmath");
const rc = @import("render_core.zig");
const c = rc.c;

// UI overlay: screen-space quad batching + its own pipeline/shaders, exposed
// today as ke_render_core.ui_quad/ui_draw vtable slots.
//
// NOTE (flagged, not resolved by this file split): this is a rendering
// FEATURE — a pipeline, two shaders, per-frame batching state — living on
// the "dumb" render core's public C ABI, the same shape the render-module
// side had before the §9.8 decomposition (a feature's own resources baked
// into a shared vtable/state instead of an opt-in module). Splitting it into
// its own file does not fix that; the actual fix would be an ABI change
// (removing ui_quad/ui_draw from ke_render_core's vtable and re-exposing UI
// as its own opt-in factory, mirroring tonemap/ui_module.zig's shape on the
// render_module.zig side) — deliberately not done here without sign-off,
// since every C# call site (`_core->ui_quad(...)`) would need to move.

const ui_vs_wgsl = @embedFile("ui.vs.wgsl");
const ui_fs_wgsl = @embedFile("ui.fs.wgsl");

// Resets the accumulator at the start of each frame (called by begin_frame).
fn uiReset(st: *rc.CoreState) void {
    st.ui_vertex_count = 0;
    st.ui_batch_count = 0;
}

pub fn uiQuad(self: [*c]c.ke_render_core, texture: c.ke_texture_handle,
          dst_x: f32, dst_y: f32, dst_w: f32, dst_h: f32,
          uv0: f32, uv1: f32, uv2: f32, uv3: f32,
          r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    const st = rc.coreOf(self);
    if (st.ui_vertex_count + 6 > st.ui_vertices.len) return;

    const tex_idx = if (texture.idx == c.KE_HANDLE_NONE) st.white_texture.idx else texture.idx;

    // Extend the current batch if the texture matches; otherwise open a new one.
    const need_new_batch = st.ui_batch_count == 0 or
        st.ui_batches[st.ui_batch_count - 1].texture_idx != tex_idx;
    if (need_new_batch) {
        if (st.ui_batch_count >= st.ui_batches.len) return;
        st.ui_batches[st.ui_batch_count] = .{
            .texture_idx = tex_idx,
            .first_vertex = st.ui_vertex_count,
            .vertex_count = 0,
        };
        st.ui_batch_count += 1;
    }

    const x0 = dst_x;
    const y0 = dst_y;
    const x1 = dst_x + dst_w;
    const y1 = dst_y + dst_h;
    const col = [4]f32{ r, g, b, a };

    const verts = [6]rc.UiVertex{
        .{ .position = .{ x0, y0 }, .uv = .{ uv0, uv1 }, .color = col },
        .{ .position = .{ x1, y0 }, .uv = .{ uv2, uv1 }, .color = col },
        .{ .position = .{ x1, y1 }, .uv = .{ uv2, uv3 }, .color = col },
        .{ .position = .{ x0, y0 }, .uv = .{ uv0, uv1 }, .color = col },
        .{ .position = .{ x1, y1 }, .uv = .{ uv2, uv3 }, .color = col },
        .{ .position = .{ x0, y1 }, .uv = .{ uv0, uv3 }, .color = col },
    };
    @memcpy(st.ui_vertices[st.ui_vertex_count .. st.ui_vertex_count + 6], &verts);
    st.ui_vertex_count += 6;
    st.ui_batches[st.ui_batch_count - 1].vertex_count += 6;
}

// The set-1 (texture+sampler) bind group for a texture index, built once and
// cached — UI textures (font atlases, a handful of solid-color sources) are
// stable across frames, so rebuilding every quad would be wasteful.
fn uiBindGroupFor(st: *rc.CoreState, tex_idx: u32) c.ke_gpu_bind_group {
    if (st.ui_bind_group_cache[tex_idx] != c.KE_GPU_INVALID_HANDLE)
        return st.ui_bind_group_cache[tex_idx];

    const view = (st.textureAt(tex_idx) orelse &st.textures[st.white_texture.idx]).view;
    const entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = view, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = st.sampler },
    };
    // No out_error slot on this lazy-cache path (uiQuad, its only caller, is a
    // void draw-call helper) — pass null. The push/pop error scope inside
    // create_bind_group still prevents the uncaptured-error abort either way;
    // only the descriptive ke_error is lost here.
    const bg = st.device.create_bind_group.?(st.device, &c.ke_gpu_bind_group_params{
        .layout = st.ui_bgl_tex,
        .entry_count = 2,
        .entries = &entries,
    }, null);
    st.ui_bind_group_cache[tex_idx] = bg;
    return bg;
}

// Pipeline + buffers for the UI overlay pass. Called once from core create.
// Premultiplied-alpha blend so both solid quads and glyph coverage composite
// correctly over whatever the tonemap pass already wrote.
pub fn uiSetup(st: *rc.CoreState, out_error: [*c][*c]c.ke_error) bool {
    const dev = st.device;

    const vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(ui_vs_wgsl), .byte_size = ui_vs_wgsl.len, .entry_point = "ui.vs" }, out_error);
    defer dev.destroy_shader_module.?(dev, vs);
    const fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(ui_fs_wgsl), .byte_size = ui_fs_wgsl.len, .entry_point = "ui.fs" }, out_error);
    defer dev.destroy_shader_module.?(dev, fs);

    const frame_bgl_entry = c.ke_gpu_bind_group_layout_entry{
        .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0,
    };
    st.ui_bgl_frame = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 1,
        .entries = &frame_bgl_entry,
    });

    const tex_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_2D },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    st.ui_bgl_tex = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 2,
        .entries = &tex_bgl_entries,
    });

    const attrs = [_]c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = @offsetOf(rc.UiVertex, "position") },
        .{ .shader_location = 1, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = @offsetOf(rc.UiVertex, "uv") },
        .{ .shader_location = 2, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X4, .offset = @offsetOf(rc.UiVertex, "color") },
    };
    const vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = @sizeOf(rc.UiVertex),
        .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 3,
        .attributes = &attrs,
    };

    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = &vbl;
    pp.bind_group_layouts[0] = st.ui_bgl_frame;
    pp.bind_group_layouts[1] = st.ui_bgl_tex;
    pp.bind_group_layout_count = 2;
    // Premultiplied-alpha over: dst = src + dst*(1-src.a). The color channel
    // reads ONE (not SRC_ALPHA) because uiQuad's caller already premultiplies.
    pp.blend_state.blend_enabled = 1;
    pp.blend_state.src_color = c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_color = c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.color_op = c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.src_alpha = c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_alpha = c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.alpha_op = c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 0;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    pp.color_target_format = 0; // swapchain surface format (backbuffer)

    st.ui_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (st.ui_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "ui pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    st.ui_frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = 64, // float4x4
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (st.ui_frame_uniform == c.KE_GPU_INVALID_HANDLE) return false;

    const frame_entry = c.ke_gpu_bind_group_entry{
        .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .buffer = st.ui_frame_uniform, .buffer_offset = 0, .buffer_size = 64,
        .texture_view = 0, .sampler = 0,
    };
    st.ui_frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = st.ui_bgl_frame,
        .entry_count = 1,
        .entries = &frame_entry,
    }, out_error);
    if (st.ui_frame_bind_group == c.KE_GPU_INVALID_HANDLE) return false;

    st.ui_vbo = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = st.ui_vertices.len * @sizeOf(rc.UiVertex),
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (st.ui_vbo == c.KE_GPU_INVALID_HANDLE) return false;

    st.ui_vertex_count = 0;
    st.ui_batch_count = 0;
    for (&st.ui_bind_group_cache) |*e| e.* = c.KE_GPU_INVALID_HANDLE;
    return true;
}

// Uploads this frame's accumulated quads and draws each texture batch. Called
// by the module's "render.ui" pass — after uiQuad calls from earlier systems
// (the wave builder orders it last by cmd_slot, see ui_module.zig).
pub fn uiDraw(self: [*c]c.ke_render_core, sys: ?*c.ke_system_ctx, io: [*c]const c.ke_render_pass_io) callconv(.c) void {
    const st = rc.coreOf(self);
    if (st.ui_vertex_count == 0) return;

    const pc = self.*.begin_pass.?(self, sys, io);
    if (pc == null) return;

    // Pixel-space (top-left origin) → clip space, honoring the backend's NDC.
    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    var proj = zm.orthographicOffCenterLh(0.0, @floatFromInt(bw), 0.0, @floatFromInt(bh), 0.0, 1.0);
    if (st.ndc.y_flip != 0) proj[1][1] = -proj[1][1];
    var proj_arr: [16]f32 = undefined;
    zm.storeMat(proj_arr[0..], proj);
    self.*.upload.?(self, st.ui_frame_uniform, 0, &proj_arr, 64);

    const bytes = std.mem.sliceAsBytes(st.ui_vertices[0..st.ui_vertex_count]);
    self.*.upload.?(self, st.ui_vbo, 0, bytes.ptr, bytes.len);

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, st.ui_pipeline);
    rp.*.set_bind_group.?(rp, 0, st.ui_frame_bind_group, null, 0);
    rp.*.set_vertex_buffer.?(rp, 0, st.ui_vbo, 0);

    var i: u32 = 0;
    while (i < st.ui_batch_count) : (i += 1) {
        const batch = st.ui_batches[i];
        rp.*.set_bind_group.?(rp, 1, uiBindGroupFor(st, batch.texture_idx), null, 0);
        rp.*.draw.?(rp, batch.vertex_count, 1, batch.first_vertex, 0);
    }
    rp.*.end.?(rp);
    self.*.end_pass.?(self, pc);

    // Vertex/batch data is already copied into the upload arena (uploadBuffer
    // memcpy's synchronously) and the draw commands reference GPU buffer handles,
    // not this CPU array — safe to reset now, ready for the next frame's queuing.
    uiReset(st);
}
