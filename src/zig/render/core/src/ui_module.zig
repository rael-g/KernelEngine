const std = @import("std");
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

// UI overlay — screen-space quad batching + its own pipeline/shaders, drawn
// after tonemap so it composites over the rendered scene. Previously this was
// baked into ke_render_core's own vtable (ui_quad/ui_draw) — a rendering
// feature (a pipeline, two shaders, per-frame batching state) embedded in the
// "dumb" core, the same shape §9.8 already diagnosed and fixed one layer up.
// Moved here so UI is an opt-in module like tonemap/forward/shadow: the core
// only provides the mechanism (begin_pass/upload/end_pass) this module calls,
// same as every other feature pass. ke_render_module_ui_quad (the ABI entry
// game code calls) forwards straight into this module's quad accumulator.

const ui_vs_wgsl = @embedFile("ui.vs.wgsl");
const ui_fs_wgsl = @embedFile("ui.fs.wgsl");

// 6 vertices per quad (two triangles, no index buffer — the per-frame count is
// small enough that indexing isn't worth the complexity).
const MAX_UI_QUADS = 8192;
const MAX_UI_BATCHES = 512;
const MAX_UI_TEXTURES = 256; // bind-group cache size — must cover every texture handle a quad might reference

const UiVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
};
const UiBatch = struct {
    texture_idx: u32,
    first_vertex: u32,
    vertex_count: u32,
};

pub const UiModule = struct {
    core: c.ke_render_core_handle = undefined,
    device: *c.ke_gpu_device = undefined,
    ndc: c.ke_ndc_convention = undefined,
    logger: ?*c.ke_logger = null,

    pipeline: c.ke_gpu_pipeline = c.KE_GPU_INVALID_HANDLE,
    bgl_frame: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE, // set 0: proj uniform
    bgl_tex: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE, // set 1: texture + sampler
    frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    frame_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    vbo: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    vertices: [MAX_UI_QUADS * 6]UiVertex = undefined,
    vertex_count: u32 = 0,
    // Consecutive same-texture quads batch into one draw call (sprite-batching —
    // texture switches are the only thing that splits a batch). Sized generously;
    // a caller alternating textures every quad still degrades gracefully (no
    // crash, just more draw calls up to MAX_UI_BATCHES).
    batches: [MAX_UI_BATCHES]UiBatch = undefined,
    batch_count: u32 = 0,
    bind_group_cache: [MAX_UI_TEXTURES]c.ke_gpu_bind_group = undefined, // lazily built, keyed by texture index; INVALID_HANDLE = unbuilt

    writes: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [1]c.ke_component_access = undefined,
};

// Resets the accumulator at the start of each frame — called at the end of
// system() (draw), not at frame-begin: resetting at frame-begin would wipe
// quads a system in an EARLIER phase queued for THIS frame's ui pass to draw,
// since begin_frame has no ordering guarantee relative to other modules.
fn uiReset(ui: *UiModule) void {
    ui.vertex_count = 0;
    ui.batch_count = 0;
}

pub fn uiQuad(ui: *UiModule, texture: c.ke_texture_handle,
          dst_x: f32, dst_y: f32, dst_w: f32, dst_h: f32,
          uv0: f32, uv1: f32, uv2: f32, uv3: f32,
          r: f32, g: f32, b: f32, a: f32) void {
    if (ui.vertex_count + 6 > ui.vertices.len) return;

    // White (handle 0, the core's built-in) is the flat-color default: a quad
    // with no texture assigned samples white*color.
    const tex_idx = if (texture.idx == c.KE_HANDLE_NONE) 0 else texture.idx;
    if (tex_idx >= MAX_UI_TEXTURES) return;

    // Extend the current batch if the texture matches; otherwise open a new one.
    const need_new_batch = ui.batch_count == 0 or
        ui.batches[ui.batch_count - 1].texture_idx != tex_idx;
    if (need_new_batch) {
        if (ui.batch_count >= ui.batches.len) return;
        ui.batches[ui.batch_count] = .{
            .texture_idx = tex_idx,
            .first_vertex = ui.vertex_count,
            .vertex_count = 0,
        };
        ui.batch_count += 1;
    }

    const x0 = dst_x;
    const y0 = dst_y;
    const x1 = dst_x + dst_w;
    const y1 = dst_y + dst_h;
    const col = [4]f32{ r, g, b, a };

    const verts = [6]UiVertex{
        .{ .position = .{ x0, y0 }, .uv = .{ uv0, uv1 }, .color = col },
        .{ .position = .{ x1, y0 }, .uv = .{ uv2, uv1 }, .color = col },
        .{ .position = .{ x1, y1 }, .uv = .{ uv2, uv3 }, .color = col },
        .{ .position = .{ x0, y0 }, .uv = .{ uv0, uv1 }, .color = col },
        .{ .position = .{ x1, y1 }, .uv = .{ uv2, uv3 }, .color = col },
        .{ .position = .{ x0, y1 }, .uv = .{ uv0, uv3 }, .color = col },
    };
    @memcpy(ui.vertices[ui.vertex_count .. ui.vertex_count + 6], &verts);
    ui.vertex_count += 6;
    ui.batches[ui.batch_count - 1].vertex_count += 6;
}

// The set-1 (texture+sampler) bind group for a texture index, built once and
// cached — UI textures (font atlases, a handful of solid-color sources) are
// stable across frames, so rebuilding every quad would be wasteful.
fn uiBindGroupFor(ui: *UiModule, tex_idx: u32) c.ke_gpu_bind_group {
    if (ui.bind_group_cache[tex_idx] != c.KE_GPU_INVALID_HANDLE)
        return ui.bind_group_cache[tex_idx];

    const view = ui.core.ref.*.texture_view.?(ui.core.ref, .{ .idx = tex_idx });
    const entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = view, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = ui.core.ref.*.sampler.?(ui.core.ref) },
    };
    // No out_error slot on this lazy-cache path (uiQuad, its only caller, is a
    // void draw-call helper) — pass null. The push/pop error scope inside
    // create_bind_group still prevents the uncaptured-error abort either way;
    // only the descriptive ke_error is lost here.
    const bg = ui.device.create_bind_group.?(ui.device, &c.ke_gpu_bind_group_params{
        .layout = ui.bgl_tex,
        .entry_count = 2,
        .entries = &entries,
    }, null);
    ui.bind_group_cache[tex_idx] = bg;
    return bg;
}

inline fn moduleOf(user: ?*anyopaque) *UiModule {
    return @alignCast(@ptrCast(user.?));
}

// Uploads this frame's accumulated quads and draws each texture batch — the
// "render.ui" runtime system.
pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const ui = moduleOf(user);
    const core = ui.core.ref;
    if (ui.vertex_count == 0) return;

    const pc = core.*.begin_pass.?(core, ctx, &ui.io);
    if (pc == null) return;

    // Pixel-space (top-left origin) → clip space, honoring the backend's NDC.
    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    var proj = zm.orthographicOffCenterLh(0.0, @floatFromInt(bw), 0.0, @floatFromInt(bh), 0.0, 1.0);
    if (ui.ndc.y_flip != 0) proj[1][1] = -proj[1][1];
    var proj_arr: [16]f32 = undefined;
    zm.storeMat(proj_arr[0..], proj);
    core.*.upload.?(core, ui.frame_uniform, 0, &proj_arr, 64);

    const bytes = std.mem.sliceAsBytes(ui.vertices[0..ui.vertex_count]);
    core.*.upload.?(core, ui.vbo, 0, bytes.ptr, bytes.len);

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, ui.pipeline);
    rp.*.set_bind_group.?(rp, 0, ui.frame_bind_group, null, 0);
    rp.*.set_vertex_buffer.?(rp, 0, ui.vbo, 0);

    var i: u32 = 0;
    while (i < ui.batch_count) : (i += 1) {
        const batch = ui.batches[i];
        rp.*.set_bind_group.?(rp, 1, uiBindGroupFor(ui, batch.texture_idx), null, 0);
        rp.*.draw.?(rp, batch.vertex_count, 1, batch.first_vertex, 0);
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);

    // Vertex/batch data is already copied into the upload arena (upload() memcpy's
    // synchronously) and the draw commands reference GPU buffer handles, not this
    // CPU array — safe to reset now, ready for the next frame's queuing.
    uiReset(ui);
}

// Pipeline + buffers for the UI overlay pass. Premultiplied-alpha blend so
// both solid quads and glyph coverage composite correctly over whatever the
// tonemap pass already wrote.
pub fn setup(ui: *UiModule, dev: *c.ke_gpu_device, core: c.ke_render_core_handle,
             ndc: c.ke_ndc_convention, logger: ?*c.ke_logger, bb_cid: c.ke_component_id,
             cmd_slot: u32, out_error: [*c][*c]c.ke_error) bool {
    ui.core = core;
    ui.device = dev;
    ui.ndc = ndc;
    ui.logger = logger;

    const vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(ui_vs_wgsl), .byte_size = ui_vs_wgsl.len, .entry_point = "ui.vs" }, out_error);
    defer dev.destroy_shader_module.?(dev, vs);
    const fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(ui_fs_wgsl), .byte_size = ui_fs_wgsl.len, .entry_point = "ui.fs" }, out_error);
    defer dev.destroy_shader_module.?(dev, fs);

    const frame_bgl_entry = c.ke_gpu_bind_group_layout_entry{
        .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0,
    };
    ui.bgl_frame = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 1,
        .entries = &frame_bgl_entry,
    });

    const tex_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_2D },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    ui.bgl_tex = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 2,
        .entries = &tex_bgl_entries,
    });

    const attrs = [_]c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = @offsetOf(UiVertex, "position") },
        .{ .shader_location = 1, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = @offsetOf(UiVertex, "uv") },
        .{ .shader_location = 2, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X4, .offset = @offsetOf(UiVertex, "color") },
    };
    const vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = @sizeOf(UiVertex),
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
    pp.bind_group_layouts[0] = ui.bgl_frame;
    pp.bind_group_layouts[1] = ui.bgl_tex;
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
    pp.color_target_formats[0] = 0; // swapchain surface format (backbuffer)
    pp.color_target_count = 1;

    ui.pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (ui.pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "ui pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    ui.frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = 64, // float4x4
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (ui.frame_uniform == c.KE_GPU_INVALID_HANDLE) return false;

    const frame_entry = c.ke_gpu_bind_group_entry{
        .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .buffer = ui.frame_uniform, .buffer_offset = 0, .buffer_size = 64,
        .texture_view = 0, .sampler = 0,
    };
    ui.frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = ui.bgl_frame,
        .entry_count = 1,
        .entries = &frame_entry,
    }, out_error);
    if (ui.frame_bind_group == c.KE_GPU_INVALID_HANDLE) return false;

    ui.vbo = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = ui.vertices.len * @sizeOf(UiVertex),
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (ui.vbo == c.KE_GPU_INVALID_HANDLE) return false;

    ui.vertex_count = 0;
    ui.batch_count = 0;
    for (&ui.bind_group_cache) |*e| e.* = c.KE_GPU_INVALID_HANDLE;

    // UI overlay pass: loads (doesn't clear) the backbuffer tonemap just wrote,
    // so text/quads composite on top.
    ui.writes = .{"backbuffer"};
    ui.io = std.mem.zeroes(c.ke_render_pass_io);
    ui.io.writes = @ptrCast(&ui.writes);
    ui.io.writes_count = 1;
    ui.io.cmd_slot = cmd_slot;
    ui.io.load = 1; // loads (doesn't clear) — composites over the tonemapped scene
    ui.access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
    };
    return true;
}
