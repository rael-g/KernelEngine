//! The UI pass: draws the entities carrying a UI quad component or a label component as
//! alpha-blended textured triangles over the backbuffer, and shapes labels from registered fonts.
//! It also owns the creation and teardown of that pass, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_ui").logFn };

const zm = @import("zmath");
const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_render_ui_factory = @import("abi_render_ui_factory");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_text = @import("abi_text");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_ui);
const handles = @import("handle");

const heap = @import("heap");
const gpa = heap.gpa;

/// One vertex as `system` writes it into the vertex buffer. Declared extern so the offsets
/// that `setup` gives the pipeline are the offsets of these bytes.
const UiVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
};
/// A run of consecutive entries of `vertices` that share one texture, drawn by one call.
const UiBatch = struct {
    texture: abi_render.ke_texture_handle,
    first_vertex: u32,
    vertex_count: u32,
};

const UiQuadComponent = abi_render.ke_ui_quad_component;

/// One entry of `fonts`. `key` and `glyphs` are copies owned by the state and freed by
/// `destroyState`. `atlas` is stored as the caller gave it and is not owned here.
const UiFont = struct {
    key: []u8 = &.{},
    atlas: abi_render.ke_texture_handle = undefined,
    glyphs: []abi_text.ke_glyph_metrics = &.{},
    line_height: f32 = 0,
    ascent: f32 = 0,
    in_use: bool = false,
};

/// Everything the pass owns. It is allocated by `ke_render_ui_create` and freed by `destroyHandle`,
/// or by the create itself when it fails. The handle's reference is `api`, whose `handle` points
/// back at the state. `io` and `access` are filled once by `setup`. The query declarations are filled by
/// the create and passed to the registrations by address. `vertices` and `batches` are rewritten by
/// `system` on every frame. `destroyHandle` unregisters the two systems before it frees the state.
const UiState = struct {
    api: abi_render_ui_factory.ke_render_ui = undefined,
    runtime: *abi_runtime.ke_runtime = undefined,
    systems: [2]abi_runtime.ke_system_id = .{ 0, 0 },

    core: *abi_render.ke_render_service = undefined,
    device: *abi_render.ke_gpu_device = undefined,
    ndc: abi_render.ke_ndc_convention = undefined,
    pipeline_params: abi_render.ke_gpu_render_pipeline_params = undefined,
    binder: *abi_render.ke_render_resource_binder = undefined,
    layout: abi_render.ke_render_shader_layout = abi_render.KE_RENDER_BINDING_INVALID,
    frame_uniform: abi_render.ke_gpu_buffer = abi_render.KE_GPU_INVALID_HANDLE,
    frame_set: abi_render.ke_render_resource_set = abi_render.KE_RENDER_BINDING_INVALID,
    vbo: abi_render.ke_gpu_buffer = abi_render.KE_GPU_INVALID_HANDLE,
    vbo_bytes: usize = 0,

    vertices: std.ArrayList(UiVertex) = .empty,
    batches: std.ArrayList(UiBatch) = .empty,
    set_cache: std.AutoHashMapUnmanaged(u32, abi_render.ke_render_resource_set) = .empty,

    fonts: std.ArrayList(UiFont) = .empty,

    io: abi_render.ke_render_pass_io = std.mem.zeroes(abi_render.ke_render_pass_io),
    access: [2]abi_runtime.ke_component_access = undefined,
    queries_terms: [2]abi_runtime.ke_component_access = undefined,
    queries: [2]abi_runtime.ke_query_decl = undefined,
    quad_cid: abi_ecs.ke_component_id = 0,
    label_cid: abi_ecs.ke_component_id = 0,
    label_shape_queries_terms: [1]abi_runtime.ke_component_access = undefined,
    label_shape_queries: [1]abi_runtime.ke_query_decl = undefined,
};

/// Recovers the state from the `handle` of its `api` field, which points back at it.
fn stateOf(self: [*c]abi_render_ui_factory.ke_render_ui) *UiState {
    return @ptrCast(@alignCast(self.*.handle));
}

/// Called through the `load_font` slot. A key already in use writes that font's handle, and the
/// glyph table given with the call is not copied again. The copies made here are released by
/// `destroyState`. A table, key or glyphs that cannot be kept fail as out of memory.
fn uiLoadFont(self: [*c]abi_render_ui_factory.ke_render_ui, key: [*c]const u8, atlas: abi_render.ke_texture_handle,
              glyphs: [*c]const abi_text.ke_glyph_metrics, glyph_count: u32,
              line_height: f32, ascent: f32, out_font: [*c]abi_render.ke_ui_font_handle) callconv(.c) abi_result.ke_result {
    const out = out_font orelse return R.code(error.InvalidArgument);
    out.* = abi_render.KE_UI_FONT_NONE;
    if (self == null or key == null or (glyph_count != 0 and glyphs == null)) return R.code(error.InvalidArgument);
    out.* = .{ .bits = loadFont(stateOf(self), std.mem.span(key), atlas, glyphs, glyph_count, line_height, ascent) catch |err| return R.code(err) };
    return R.ok;
}

fn loadFont(ui: *UiState, key_slice: []const u8, atlas: abi_render.ke_texture_handle, glyphs: [*c]const abi_text.ke_glyph_metrics, glyph_count: u32, line_height: f32, ascent: f32) R.Error!u32 {
    for (ui.fonts.items, 0..) |f, i| {
        if (f.in_use and std.mem.eql(u8, f.key, key_slice))
            return handles.make(@intCast(i), abi_render.KE_HANDLE_GENERATION_FIRST);
    }

    var slot: ?usize = null;
    for (ui.fonts.items, 0..) |f, i| {
        if (!f.in_use) { slot = i; break; }
    }
    const idx = slot orelse blk: {
        try ui.fonts.append(gpa, .{});
        break :blk ui.fonts.items.len - 1;
    };

    const owned_key = try gpa.dupe(u8, key_slice);
    errdefer gpa.free(owned_key);
    const owned_glyphs = try gpa.dupe(abi_text.ke_glyph_metrics, if (glyph_count == 0) &.{} else glyphs[0..glyph_count]);

    ui.fonts.items[idx] = .{
        .key = owned_key,
        .atlas = atlas,
        .glyphs = owned_glyphs,
        .line_height = line_height,
        .ascent = ascent,
        .in_use = true,
    };
    return handles.make(@intCast(idx), abi_render.KE_HANDLE_GENERATION_FIRST);
}

fn findGlyph(glyphs: []const abi_text.ke_glyph_metrics, codepoint: u32) ?abi_text.ke_glyph_metrics {
    for (glyphs) |g| {
        if (g.codepoint == codepoint) return g;
    }
    return null;
}

/// Called by `labelShapeSystem` for each label. It writes the glyph quads into the label component
/// itself: when it returns, `glyph_count` is the number of those quads that `system` will draw.
fn shapeLabel(ui: *UiState, l_ptr: [*c]abi_render.ke_label_component, bb_w: u32, bb_h: u32) void {
    const l: *abi_render.ke_label_component = @ptrCast(l_ptr);
    l.glyph_count = 0;

    const font_idx = handles.index(l.font_handle.bits);
    if (l.font_handle.bits == abi_render.KE_HANDLE_NONE or font_idx >= ui.fonts.items.len or !ui.fonts.items[font_idx].in_use)
        return;
    const font = &ui.fonts.items[font_idx];

    const text = std.mem.sliceTo(&l.text, 0);
    if (text.len == 0) return;

    var text_width: f32 = 0;
    for (text) |ch| {
        if (findGlyph(font.glyphs, ch)) |g| text_width += g.advance_x;
    }

    const anchor_x = l.anchor[0] * @as(f32, @floatFromInt(bb_w)) + l.offset[0];
    const anchor_y = l.anchor[1] * @as(f32, @floatFromInt(bb_h)) + l.offset[1];
    const pivot_x = l.anchor[0] * text_width;
    const pivot_y = l.anchor[1] * font.ascent;
    const origin_x = anchor_x - pivot_x;
    const baseline_y = anchor_y - pivot_y + font.ascent;

    var pen = origin_x;
    var slot: u32 = 0;
    for (text) |ch| {
        if (slot >= abi_render.KE_LABEL_MAX_GLYPHS) break;
        const g = findGlyph(font.glyphs, ch) orelse {
            pen += font.line_height * 0.25;
            continue;
        };
        l.glyphs[slot] = .{
            .dst_x = pen + g.bearing_x,
            .dst_y = baseline_y - g.bearing_y,
            .dst_w = g.width,
            .dst_h = g.height,
            .u0 = g.u0, .v0 = g.v0, .u1 = g.u1, .v1 = g.v1,
        };
        pen += g.advance_x;
        slot += 1;
    }
    l.glyph_count = slot;
}

const shader_layout = abi_render.ke_render_shader_layout_params{
    .shader = "ui",
    .stages = abi_render.KE_GPU_SHADER_STAGE_VERTEX | abi_render.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = null,
    .hint_count = 0,
};

/// Called by `system` for each batch, with the set of a texture built on first use and cached by
/// the texture's index. A set that cannot be created is not kept, and the next draw of that slot
/// creates it again.
fn uiSetFor(ui: *UiState, tex: abi_render.ke_texture_handle) abi_render.ke_render_resource_set {
    if (ui.set_cache.get(tex.bits)) |cached| return cached;

    const view = ui.core.*.texture_view.?(ui.core, tex);
    const bindings = [_]abi_render.ke_render_shader_binding{
        .{ .name = "t_tex", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = view, .sampler = 0 },
    };
    var set: abi_render.ke_render_resource_set = abi_render.KE_RENDER_BINDING_INVALID;
    if (ui.binder.create_set.?(ui.binder, ui.layout, "tex", "ui.tex_set", &bindings, bindings.len, &set) != R.ok) return abi_render.KE_RENDER_BINDING_INVALID;
    ui.set_cache.put(gpa, tex.bits, set) catch {
        ui.binder.destroy_set.?(ui.binder, set);
        return abi_render.KE_RENDER_BINDING_INVALID;
    };
    return set;
}

/// The user pointer both systems receive is the `UiState` itself, set by `ke_render_ui_create`.
inline fn moduleOf(user: ?*anyopaque) *UiState {
    return @alignCast(@ptrCast(user.?));
}

/// Called by `system` for each quad and each glyph. A null texture is drawn with the white texture.
/// Returns false when the vertex or batch list cannot grow.
fn emitQuad(ui: *UiState, tex_in: abi_render.ke_texture_handle,
            x0: f32, y0: f32, x1: f32, y1: f32, tu0: f32, tv0: f32, tu1: f32, tv1: f32, color: [4]f32) bool {
    const tex = if (tex_in.bits == abi_render.KE_HANDLE_NONE) ui.core.*.white_texture.?(ui.core) else tex_in;
    const first: u32 = @intCast(ui.vertices.items.len);
    const need_new_batch = ui.batches.items.len == 0 or ui.batches.items[ui.batches.items.len - 1].texture.bits != tex.bits;
    if (need_new_batch) {
        ui.batches.append(gpa, .{ .texture = tex, .first_vertex = first, .vertex_count = 0 }) catch return false;
    }
    ui.vertices.appendSlice(gpa, &[6]UiVertex{
        .{ .position = .{ x0, y0 }, .uv = .{ tu0, tv0 }, .color = color },
        .{ .position = .{ x1, y0 }, .uv = .{ tu1, tv0 }, .color = color },
        .{ .position = .{ x1, y1 }, .uv = .{ tu1, tv1 }, .color = color },
        .{ .position = .{ x0, y0 }, .uv = .{ tu0, tv0 }, .color = color },
        .{ .position = .{ x1, y1 }, .uv = .{ tu1, tv1 }, .color = color },
        .{ .position = .{ x0, y1 }, .uv = .{ tu0, tv1 }, .color = color },
    }) catch return false;
    ui.batches.items[ui.batches.items.len - 1].vertex_count += 6;
    return true;
}

/// Makes the vertex buffer hold `bytes`, replacing it with one of the next power of two size when
/// it is smaller. Fails with the device's code, keeping the buffer it had.
fn ensureVertexBuffer(ui: *UiState, bytes: usize) R.Error!void {
    if (bytes <= ui.vbo_bytes) return;
    const size = std.math.ceilPowerOfTwoAssert(usize, bytes);
    const dev = ui.device;
    var vbo: abi_render.ke_gpu_buffer = undefined;
    try R.check(dev.create_buffer.?(dev, &abi_render.ke_gpu_buffer_params{
        .label = "ui.vbo",
        .initial_data = null,
        .size = size,
        .usage = abi_render.KE_GPU_BUFFER_USAGE_VERTEX | abi_render.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &vbo));
    if (ui.vbo != abi_render.KE_GPU_INVALID_HANDLE) dev.destroy_buffer.?(dev, ui.vbo);
    ui.vbo = vbo;
    ui.vbo_bytes = size;
}

/// Registered by `ke_render_ui_create` for the update phase, with write access to the label
/// component only. Shapes every label against the current backbuffer size, so a resize is picked
/// up on the next frame. It succeeds on every path, including when the view is empty.
fn labelShapeSystem(ctx: ?*abi_runtime.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const ui = moduleOf(user);

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    if (segc == 0) return R.ok;

    var bw: u32 = 0;
    var bh: u32 = 0;
    ui.core.*.backbuffer_size.?(ui.core, &bw, &bh);

    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const labels: [*c]abi_render.ke_label_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            shapeLabel(ui, labels + i, bw, bh);
        }
    }
    return R.ok;
}

/// Registered by `ke_render_ui_create` for the render phase, reading quads and labels. Quads with
/// no area are skipped and glyphs are drawn in the premultiplied label color. With nothing emitted
/// the pass ends without drawing; otherwise the projection (flipped on Y when the ndc convention
/// asks) and the vertices are uploaded and each batch is drawn with its texture's set. It
/// succeeds when the render service yields no pass to draw into, and fails as out of memory when
/// the vertex list cannot grow and with the device's code when the vertex buffer cannot.
fn system(ctx: ?*abi_runtime.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const ui = moduleOf(user);
    const core = ui.core;

    var quad_segc: usize = 0;
    const quad_segs = ctx.?.view.?(ctx, 0, &quad_segc);
    var label_segc: usize = 0;
    const label_segs = ctx.?.view.?(ctx, 1, &label_segc);
    if (quad_segc == 0 and label_segc == 0) return R.ok;

    const pc = core.*.begin_pass.?(core, &ui.io);
    if (pc == null) return R.ok;

    ui.vertices.clearRetainingCapacity();
    ui.batches.clearRetainingCapacity();
    var emitted = true;

    var s: usize = 0;
    while (emitted and s < quad_segc) : (s += 1) {
        const quads: [*c]const UiQuadComponent = @ptrCast(@alignCast(quad_segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < quad_segs.?[s].count) : (i += 1) {
            const q = quads[i];
            if (q.dst_w <= 0 or q.dst_h <= 0) continue;
            emitted = emitQuad(ui, .{ .bits = q.texture_bits },
                q.dst_x, q.dst_y, q.dst_x + q.dst_w, q.dst_y + q.dst_h,
                q.u0, q.v0, q.u1, q.v1, q.color);
            if (!emitted) break;
        }
    }

    s = 0;
    while (emitted and s < label_segc) : (s += 1) {
        const labels: [*c]const abi_render.ke_label_component = @ptrCast(@alignCast(label_segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < label_segs.?[s].count) : (i += 1) {
            const l = labels[i];
            if (l.glyph_count == 0) continue;

            const font_idx = handles.index(l.font_handle.bits);
            const tex = ui.fonts.items[font_idx].atlas;
            const premul = [4]f32{ l.color[0] * l.color[3], l.color[1] * l.color[3], l.color[2] * l.color[3], l.color[3] };

            var gi: u32 = 0;
            while (gi < l.glyph_count) : (gi += 1) {
                const g = l.glyphs[gi];
                emitted = emitQuad(ui, tex,
                    g.dst_x, g.dst_y, g.dst_x + g.dst_w, g.dst_y + g.dst_h,
                    g.u0, g.v0, g.u1, g.v1, premul);
                if (!emitted) break;
            }
        }
    }

    if (!emitted) {
        log.warn("ui pass: vertex list allocation failed", .{});
        core.*.end_pass.?(core, pc);
        return R.code(error.OutOfMemory);
    }
    if (ui.vertices.items.len == 0) {
        core.*.end_pass.?(core, pc);
        return R.ok;
    }
    const bytes = std.mem.sliceAsBytes(ui.vertices.items);
    ensureVertexBuffer(ui, bytes.len) catch |err| {
        core.*.end_pass.?(core, pc);
        return R.code(err);
    };

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.?.backbuffer_size.?(pc, &bw, &bh);
    var proj = zm.orthographicOffCenterLh(0.0, @floatFromInt(bw), 0.0, @floatFromInt(bh), 0.0, 1.0);
    if (ui.ndc.y_flip) proj[1][1] = -proj[1][1];
    var proj_arr: [16]f32 = undefined;
    zm.storeMat(proj_arr[0..], proj);
    core.*.upload.?(core, ui.frame_uniform, 0, &proj_arr, 64);

    core.*.upload.?(core, ui.vbo, 0, bytes.ptr, bytes.len);

    const rp = pc.?.begin_render.?(pc);
    rp.?.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &ui.pipeline_params));
    ui.binder.bind_render_set.?(ui.binder, rp, ui.frame_set, null, 0);
    rp.?.set_vertex_buffer.?(rp, 0, ui.vbo, 0);

    for (ui.batches.items) |batch| {
        ui.binder.bind_render_set.?(ui.binder, rp, uiSetFor(ui, batch.texture), null, 0);
        rp.?.draw.?(rp, batch.vertex_count, 1, batch.first_vertex, 0);
    }
    rp.?.end.?(rp);
    core.*.end_pass.?(core, pc);
    return R.ok;
}

/// Called once by `ke_render_ui_create`, before anything is registered. It joins the chain at the
/// overlay stage and builds the pipeline in that stage's format, then stops at the first step that
/// fails and returns false; what was built before that step stays in the state for `destroyState`
/// to release. On success `io` and `access` describe the pass that `system` begins and the write it
/// makes.
/// Joining, it tells the runtime that the chain, not the runtime, orders the writers of the
/// frame's color.
fn setup(ui: *UiState, p: *const abi_render_ui_factory.ke_render_ui_params) R.Error!void {
    const core: *abi_render.ke_render_service = p.service.?;
    const dev: *abi_render.ke_gpu_device = p.device.?;
    ui.core = core;
    ui.device = dev;
    ui.ndc = p.ndc;

    ui.io.name = "render.ui";
    try R.check(core.*.join_chain.?(core, abi_render.KE_RENDER_STAGE_OVERLAY, abi_render.KE_RENDER_CHAIN_DRAW_OVER, &ui.io.chain));
    try R.check(p.runtime.?.declare_self_ordered.?(p.runtime, core.*.cid.?(core, abi_render.KE_RENDER_FRAME_COLOR)));
    const format = core.*.chain_format.?(core, abi_render.KE_RENDER_STAGE_OVERLAY);

    var vs: abi_render.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "ui", abi_render.KE_GPU_SHADER_STAGE_VERTEX, &vs));
    var fs: abi_render.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "ui", abi_render.KE_GPU_SHADER_STAGE_FRAGMENT, &fs));

    ui.binder = core.*.resource_binder.?(core).?;
    try R.check(ui.binder.create_shader_layout.?(ui.binder, &shader_layout, &ui.layout));

    const attrs = [_]abi_render.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = abi_render.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = @offsetOf(UiVertex, "position") },
        .{ .shader_location = 1, .format = abi_render.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = @offsetOf(UiVertex, "uv") },
        .{ .shader_location = 2, .format = abi_render.KE_GPU_VERTEX_FORMAT_FLOAT32X4, .offset = @offsetOf(UiVertex, "color") },
    };
    const vbl = abi_render.ke_gpu_vertex_buffer_layout{
        .stride = @sizeOf(UiVertex),
        .step_mode = abi_render.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 3,
        .attributes = &attrs,
    };

    var pp = std.mem.zeroes(abi_render.ke_gpu_render_pipeline_params);
    pp.label = "ui.pipeline";
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = abi_render.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = abi_render.KE_GPU_CULL_MODE_NONE;
    pp.front_face = abi_render.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = (&vbl)[0..1];
    try R.check(ui.binder.pipeline_layouts.?(ui.binder, ui.layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count));
    pp.blend_state.blend_enabled = true;
    pp.blend_state.src_color = abi_render.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_color = abi_render.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.color_op = abi_render.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.src_alpha = abi_render.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_alpha = abi_render.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.alpha_op = abi_render.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = false;
    pp.depth_stencil.depth_write_enabled = false;
    pp.depth_stencil.depth_compare = abi_render.KE_GPU_COMPARE_ALWAYS;
    pp.color_target_formats[0] = format;
    pp.color_target_count = 1;

    ui.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &ui.pipeline_params) == abi_render.KE_GPU_INVALID_HANDLE) {
        log.warn("ui pass: render pipeline creation failed", .{});
        return error.NotInitialized;
    }

    try R.check(dev.create_buffer.?(dev, &abi_render.ke_gpu_buffer_params{
        .label = "ui.frame_uniform",
        .initial_data = null,
        .size = 64,
        .usage = abi_render.KE_GPU_BUFFER_USAGE_UNIFORM | abi_render.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &ui.frame_uniform));

    const frame_binding = [_]abi_render.ke_render_shader_binding{
        .{ .name = "frame", .buffer = ui.frame_uniform, .buffer_offset = 0, .buffer_size = 64, .texture_view = 0, .sampler = 0 },
    };
    try R.check(ui.binder.create_set.?(ui.binder, ui.layout, null, "ui.frame_set", &frame_binding, frame_binding.len, &ui.frame_set));

    try ensureVertexBuffer(ui, 6 * @sizeOf(UiVertex));

    ui.access = .{
        .{ .cid = core.*.cid.?(core, abi_render.KE_RENDER_FRAME_COLOR), .access = abi_runtime.KE_ACCESS_WRITE },
        .{ .cid = p.frame_cid, .access = abi_runtime.KE_ACCESS_READ },
    };
}

/// Safe on a partly built state: each GPU object, set and layout is released only if `setup` had
/// created it.
fn destroyState(ui: *UiState) void {
    if (ui.io.chain != abi_render.KE_RENDER_CHAIN_NONE) ui.core.*.leave_chain.?(ui.core, ui.io.chain);
    const dev = ui.device;
    const invalid = abi_render.KE_GPU_INVALID_HANDLE;
    if (ui.frame_uniform != invalid) dev.destroy_buffer.?(dev, ui.frame_uniform);
    if (ui.vbo != invalid) dev.destroy_buffer.?(dev, ui.vbo);
    if (ui.layout != abi_render.KE_RENDER_BINDING_INVALID) {
        ui.binder.destroy_set.?(ui.binder, ui.frame_set);
        var cached = ui.set_cache.valueIterator();
        while (cached.next()) |set| ui.binder.destroy_set.?(ui.binder, set.*);
        ui.binder.destroy_shader_layout.?(ui.binder, ui.layout);
    }
    ui.set_cache.deinit(gpa);
    ui.vertices.deinit(gpa);
    ui.batches.deinit(gpa);
    defer ui.fonts.deinit(gpa);
    for (ui.fonts.items) |f| {
        if (f.in_use) {
            gpa.free(f.key);
            gpa.free(f.glyphs);
        }
    }
}

/// The destroy slot of the handle that `ke_render_ui_create` returns.
fn destroyHandle(self: ?*abi_render_ui_factory.ke_render_ui) callconv(.c) void {
    const ui = stateOf(self orelse return);
    for (ui.systems) |id| _ = ui.runtime.unregister_system.?(ui.runtime, id);
    destroyState(ui);
    gpa.destroy(ui);
}

/// A missing runtime, ecs, service, device or output fails as an invalid argument and a state that
/// cannot be allocated as out of memory. On success it has registered the quad and label components
/// with the ecs and two systems with the runtime: `labelShapeSystem` in the update phase and
/// `system` in the render phase. A failing `setup`, component or system registration fails with its
/// code and leaves the handle zeroed, and a refused second system takes the first back. On success
/// the returned handle owns the state until its destroy slot runs.
export fn ke_render_ui_create(params_in: ?*const abi_render_ui_factory.ke_render_ui_params, out_ui: [*c]abi_render_ui_factory.ke_render_ui_handle) callconv(.c) abi_result.ke_result {
    const out = out_ui orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    const e: *abi_ecs.ke_ecs = p.ecs orelse return R.code(error.InvalidArgument);
    if (p.service == null or p.device == null) return R.code(error.InvalidArgument);

    const ui = gpa.create(UiState) catch |err| return R.code(err);
    ui.* = .{};
    ui.api = .{ .handle = ui, .load_font = uiLoadFont };
    register(ui, p, rt, e) catch |err| {
        destroyState(ui);
        gpa.destroy(ui);
        return R.code(err);
    };
    out.* = .{ .ref = @ptrCast(&ui.api), .destroy = destroyHandle };
    return R.ok;
}

fn register(ui: *UiState, p: *const abi_render_ui_factory.ke_render_ui_params, rt: *abi_runtime.ke_runtime, e: *abi_ecs.ke_ecs) R.Error!void {
    try setup(ui, p);

    ui.quad_cid = abi_ecs.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.ke_component_params{ .name = abi_render.KE_COMPONENT_NAME_UI_QUAD, .size = @sizeOf(UiQuadComponent), .alignment = @alignOf(UiQuadComponent), .fields = &abi_render.ke_ui_quad_component_fields, .field_count = abi_render.ke_ui_quad_component_fields.len }, &ui.quad_cid));

    ui.label_cid = abi_ecs.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.ke_component_params{ .name = abi_render.KE_COMPONENT_NAME_LABEL, .size = @sizeOf(abi_render.ke_label_component), .alignment = @alignOf(abi_render.ke_label_component), .fields = &abi_render.ke_label_component_fields, .field_count = abi_render.ke_label_component_fields.len }, &ui.label_cid));
    ui.queries_terms = .{ .{ .cid = ui.quad_cid, .access = abi_runtime.KE_ACCESS_READ }, .{ .cid = ui.label_cid, .access = abi_runtime.KE_ACCESS_READ } };
    ui.queries = .{ .{ .terms = ui.queries_terms[0..].ptr, .term_count = 1 }, .{ .terms = ui.queries_terms[1..].ptr, .term_count = 1 } };

    var params = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    params.name = "render.ui";
    params.phase = abi_runtime.KE_PHASE_RENDER;
    params.queries = &ui.queries;
    params.query_count = ui.queries.len;
    params.access_list = &ui.access;
    params.access_count = ui.access.len;
    params.pinned_thread = 0;
    params.user_data = ui;
    params.execute = system;
    var first_system: abi_runtime.ke_system_id = 0;
    try R.check(rt.register_system.?(rt, &params, &first_system));
    errdefer _ = rt.unregister_system.?(rt, first_system);

    ui.label_shape_queries_terms = .{ .{ .cid = ui.label_cid, .access = abi_runtime.KE_ACCESS_WRITE } };
    ui.label_shape_queries = .{ .{ .terms = ui.label_shape_queries_terms[0..].ptr, .term_count = 1 } };

    var shape_params = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    shape_params.name = "render.ui.labels";
    shape_params.phase = abi_runtime.KE_PHASE_UPDATE;
    shape_params.queries = &ui.label_shape_queries;
    shape_params.query_count = ui.label_shape_queries.len;
    shape_params.pinned_thread = 0;
    shape_params.user_data = ui;
    shape_params.execute = labelShapeSystem;
    var system_id: abi_runtime.ke_system_id = 0;
    try R.check(rt.register_system.?(rt, &shape_params, &system_id));
    ui.runtime = rt;
    ui.systems = .{ first_system, system_id };
}

const testing = std.testing;

const zsub = @import("zsub");

const Rig = struct {
    dev: zsub.For(abi_render.ke_gpu_device),
    binder: zsub.For(abi_render.ke_render_resource_binder),
    core: zsub.For(abi_render.ke_render_service),
    rt: zsub.For(abi_runtime.ke_runtime),
    ecs: zsub.For(abi_ecs.ke_ecs),

    fn init(self: *Rig) !void {
        try self.dev.init();
        _ = self.dev.when(.create_buffer).writesFresh(2);
        try self.binder.init();
        _ = self.binder.when(.create_shader_layout).writesFresh(2);
        _ = self.binder.when(.create_set).writesFresh(6);
        try self.core.init();
        _ = self.core.when(.resource_binder).returns(self.binder.api());
        _ = self.core.when(.load_shader).writesFresh(3);
        _ = self.core.when(.get_or_create_pipeline).returnsFresh();
        _ = self.core.when(.cid).returnsFresh();
        _ = self.core.when(.texture_view).returnsFresh();
        _ = self.core.when(.white_texture).returns(.{ .bits = 1 });
        _ = self.core.when(.join_chain).writesFresh(3);
        _ = self.core.when(.chain_format).does(chainFormat);
        try self.rt.init();
        _ = self.rt.when(.register_system).writesFresh(2);
        try self.ecs.init();
        _ = self.ecs.when(.component_register).writesFresh(2);
    }

    fn deinit(self: *Rig) void {
        self.ecs.deinit();
        self.rt.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn expectReleased(self: *Rig) !void {
        try self.dev.received(.destroy_buffer).where(zsub.argIsNot(1, abi_render.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_buffer));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
        try self.core.received(.leave_chain).sameAs(self.core.received(.join_chain));
    }
};

fn chainFormat(args: zsub.For(abi_render.ke_render_service).Args(.chain_format)) abi_render.ke_gpu_texture_format {
    return if (args[1] >= abi_render.KE_RENDER_STAGE_TONEMAP) abi_render.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM else abi_render.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
}

test "creating and destroying the ui pass leaves no block allocated and no GPU resource live" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render_ui_factory.ke_render_ui_handle = undefined;
    try R.check(ke_render_ui_create(&.{ .runtime = rig.rt.api(), .ecs = rig.ecs.api(), .service = rig.core.api(), .device = rig.dev.api(), .ndc = std.mem.zeroes(abi_render.ke_ndc_convention), .frame_cid = 1 }, &h));
    h.destroy.?(h.ref);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "destroying the ui pass unregisters every system it registered" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render_ui_factory.ke_render_ui_handle = undefined;
    try R.check(ke_render_ui_create(&.{ .runtime = rig.rt.api(), .ecs = rig.ecs.api(), .service = rig.core.api(), .device = rig.dev.api(), .ndc = std.mem.zeroes(abi_render.ke_ndc_convention), .frame_cid = 1 }, &h));
    h.destroy.?(h.ref);
    try rig.rt.received(.register_system).atLeast(1);
    try rig.rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_runtime.ke_system_id, 0))).never();
    try rig.rt.received(.unregister_system).sameAs(rig.rt.received(.register_system));
}

test "a ui pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.KE_RESULT_GENERAL);
    var h: abi_render_ui_factory.ke_render_ui_handle = undefined;
    try testing.expect(ke_render_ui_create(&.{ .runtime = rig.rt.api(), .ecs = rig.ecs.api(), .service = rig.core.api(), .device = rig.dev.api(), .ndc = std.mem.zeroes(abi_render.ke_ndc_convention), .frame_cid = 1 }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "a ui pass the runtime refuses to register releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.rt.when(.register_system).returns(abi_result.KE_RESULT_OUT_OF_MEMORY);
    var h: abi_render_ui_factory.ke_render_ui_handle = undefined;
    try testing.expect(ke_render_ui_create(&.{ .runtime = rig.rt.api(), .ecs = rig.ecs.api(), .service = rig.core.api(), .device = rig.dev.api(), .ndc = std.mem.zeroes(abi_render.ke_ndc_convention), .frame_cid = 1 }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "a ui pass the runtime refuses its second system takes the first one back" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.rt.when(.register_system).returnsSeq(&.{ abi_result.KE_OK, abi_result.KE_RESULT_OUT_OF_MEMORY });
    var h: abi_render_ui_factory.ke_render_ui_handle = undefined;
    try testing.expect(ke_render_ui_create(&.{ .runtime = rig.rt.api(), .ecs = rig.ecs.api(), .service = rig.core.api(), .device = rig.dev.api(), .ndc = std.mem.zeroes(abi_render.ke_ndc_convention), .frame_cid = 1 }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.rt.received(.unregister_system).times(1);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}
