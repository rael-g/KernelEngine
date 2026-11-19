//! The UI pass: draws the render world's entities carrying a UI quad component or a label component
//! as alpha-blended textured triangles over the frame's output, and shapes labels from registered
//! fonts. It owns the creation and teardown of that pass and of its module, behind two factories.

const abi_render_contract = @import("abi_render_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_handles = @import("abi_render_handles");
const abi_ui_components = @import("abi_ui_components");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_ui").logFn };

const zm = @import("zmath");
const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_render_context = @import("abi_render_context");
const abi_render_ui_factory = @import("abi_render_ui_factory");
const abi_render_ui = @import("abi_render_ui");
const abi_result = @import("abi_result");
const abi_schedule = @import("abi_schedule");
const abi_module = @import("abi_module");
const abi_render_frame = @import("abi_render_frame");
const abi_render_graph = @import("abi_render_graph");
const abi_extraction = @import("abi_extraction");
const abi_text = @import("abi_text");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_ui);

const heap = @import("heap");
const gpa = heap.gpa;
const rg = abi_render_graph.c;

/// One vertex as `system` writes it into the vertex buffer. Declared extern so the offsets
/// that `setup` gives the pipeline are the offsets of these bytes.
const UiVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
};
/// A run of consecutive entries of `vertices` that share one texture, drawn by one call.
const UiBatch = struct {
    texture: abi_render_handles.c.ke_texture_handle,
    first_vertex: u32,
    vertex_count: u32,
};

const UiQuadComponent = abi_ui_components.c.ke_ui_quad_component;

/// One entry of `fonts`. `key` and `glyphs` are copies owned by the state and freed by
/// `destroyState`. `atlas` is stored as the caller gave it and is not owned here.
const UiFont = struct {
    key: []u8 = &.{},
    atlas: abi_render_handles.c.ke_texture_handle = undefined,
    glyphs: []abi_text.c.ke_glyph_metrics = &.{},
    line_height: f32 = 0,
    ascent: f32 = 0,
    in_use: bool = false,
};

/// Everything the pass owns. It is allocated by `ke_render_ui_create` and freed by `destroyHandle`,
/// or by the create itself when it fails. The handle's reference is `api`, whose `handle` points
/// back at the state, as does that of `module`. The query declarations are filled by the create and
/// passed to the registrations by address. `vertices`, `batches` and `output` are rewritten by
/// `queueSystem` on every frame, and read by `record` when the graph executes. `destroyHandle`
/// detaches the module before it frees the state.
const UiState = struct {
    api: abi_render_ui.c.ke_render_ui = undefined,
    module: abi_module.c.ke_module = undefined,
    schedule: ?*abi_schedule.c.ke_schedule = null,
    systems: [2]abi_schedule.c.ke_schedule_system_id = .{ 0, 0 },
    sets: [2]abi_schedule.c.ke_schedule_set_id = .{ 0, 0 },

    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,
    frame: *abi_render_frame.c.ke_render_frame = undefined,
    ndc: abi_render_gpu.c.ke_ndc_convention = undefined,
    pipeline_params: abi_render_gpu.c.ke_gpu_render_pipeline_desc = undefined,
    binder: *abi_render_gpu.c.ke_render_resource_binder = undefined,
    layout: abi_asset_resolver.c.ke_render_shader_layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    frame_uniform: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    frame_set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    vbo: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    vbo_bytes: usize = 0,
    output: rg.ke_render_graph_resource = rg.KE_RENDER_GRAPH_RESOURCE_INVALID,

    vertices: std.ArrayList(UiVertex) = .empty,
    batches: std.ArrayList(UiBatch) = .empty,
    set_cache: std.AutoHashMapUnmanaged(u32, abi_asset_resolver.c.ke_render_resource_set) = .empty,

    fonts: std.ArrayList(UiFont) = .empty,

    access: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    queries_terms: [2]abi_ecs.c.ke_ecs_query_term = undefined,
    queries: [2]abi_ecs.c.ke_ecs_query_desc = undefined,
    quad_cid: abi_asset_resolver.c.ke_component_id = 0,
    label_cid: abi_asset_resolver.c.ke_component_id = 0,
    label_shape_queries_terms: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    label_shape_queries: [1]abi_ecs.c.ke_ecs_query_desc = undefined,
};

/// Recovers the state from the `handle` of its `api` field, which points back at it.
fn stateOf(self: [*c]abi_render_ui.c.ke_render_ui) *UiState {
    return @ptrCast(@alignCast(self.*.handle));
}

/// Called through the `load_font` slot. A key already in use writes that font's handle, and the
/// glyph table given with the call is not copied again. The copies made here are released by
/// `destroyState`. A table, key or glyphs that cannot be kept fail as out of memory.
fn uiLoadFont(self: [*c]abi_render_ui.c.ke_render_ui, key: [*c]const u8, atlas: abi_render_handles.c.ke_texture_handle,
              glyphs: [*c]const abi_text.c.ke_glyph_metrics, glyph_count: u32,
              line_height: f32, ascent: f32, out_font: [*c]abi_ui_components.c.ke_ui_font_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_font orelse return R.code(error.InvalidArgument);
    out.* = abi_ui_components.c.KE_UI_FONT_NONE;
    if (self == null or key == null or (glyph_count != 0 and glyphs == null)) return R.code(error.InvalidArgument);
    out.* = .{ .bits = loadFont(stateOf(self), std.mem.span(key), atlas, glyphs, glyph_count, line_height, ascent) catch |err| return R.code(err) };
    return R.ok;
}

fn fontHandle(idx: usize) u32 {
    return (@as(u32, @intCast(idx)) & abi_render_handles.c.KE_HANDLE_INDEX_MASK) | (abi_render_handles.c.KE_HANDLE_GENERATION_FIRST << abi_render_handles.c.KE_HANDLE_INDEX_BITS);
}

fn loadFont(ui: *UiState, key_slice: []const u8, atlas: abi_render_handles.c.ke_texture_handle, glyphs: [*c]const abi_text.c.ke_glyph_metrics, glyph_count: u32, line_height: f32, ascent: f32) R.Error!u32 {
    for (ui.fonts.items, 0..) |f, i| {
        if (f.in_use and std.mem.eql(u8, f.key, key_slice))
            return fontHandle(i);
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
    const owned_glyphs = try gpa.dupe(abi_text.c.ke_glyph_metrics, if (glyph_count == 0) &.{} else glyphs[0..glyph_count]);

    ui.fonts.items[idx] = .{
        .key = owned_key,
        .atlas = atlas,
        .glyphs = owned_glyphs,
        .line_height = line_height,
        .ascent = ascent,
        .in_use = true,
    };
    return fontHandle(idx);
}

fn findGlyph(glyphs: []const abi_text.c.ke_glyph_metrics, codepoint: u32) ?abi_text.c.ke_glyph_metrics {
    for (glyphs) |g| {
        if (g.codepoint == codepoint) return g;
    }
    return null;
}

/// Called by `labelShapeSystem` for each label. It writes the glyph quads into the label component
/// itself: when it returns, `glyph_count` is the number of those quads that `system` will draw.
fn shapeLabel(ui: *UiState, l_ptr: [*c]abi_ui_components.c.ke_label_component, bb_w: u32, bb_h: u32) void {
    const l: *abi_ui_components.c.ke_label_component = @ptrCast(l_ptr);
    l.glyph_count = 0;

    const font_idx = l.font_handle.bits & abi_render_handles.c.KE_HANDLE_INDEX_MASK;
    if (l.font_handle.bits == abi_render_handles.c.KE_HANDLE_NONE or font_idx >= ui.fonts.items.len or !ui.fonts.items[font_idx].in_use)
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
        if (slot >= abi_ui_components.c.KE_LABEL_MAX_GLYPHS) break;
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

const shader_layout = abi_render_gpu.c.ke_render_shader_layout_desc{
    .shader = "ui",
    .stages = abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX | abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = null,
    .hint_count = 0,
};

/// Called by `system` for each batch, with the set of a texture built on first use and cached by
/// the texture's index. A set that cannot be created is not kept, and the next draw of that slot
/// creates it again.
fn uiSetFor(ui: *UiState, tex: abi_render_handles.c.ke_texture_handle) abi_asset_resolver.c.ke_render_resource_set {
    if (ui.set_cache.get(tex.bits)) |cached| return cached;

    const view = ui.core.*.texture_view.?(ui.core, tex);
    const bindings = [_]abi_render_gpu.c.ke_render_shader_binding{
        .{ .name = "t_tex", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = view, .sampler = 0 },
    };
    var set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID;
    if (ui.binder.create_set.?(ui.binder, ui.layout, "tex", "ui.tex_set", &bindings, bindings.len, &set) != R.ok) return abi_render_gpu.c.KE_RENDER_BINDING_INVALID;
    ui.set_cache.put(gpa, tex.bits, set) catch {
        ui.binder.destroy_set.?(ui.binder, set);
        return abi_render_gpu.c.KE_RENDER_BINDING_INVALID;
    };
    return set;
}

/// The user pointer both systems receive is the `UiState` itself, set by `ke_render_ui_create`.
inline fn moduleOf(user: ?*anyopaque) *UiState {
    return @alignCast(@ptrCast(user.?));
}

/// Called by `system` for each quad and each glyph. A null texture is drawn with the white texture.
/// Returns false when the vertex or batch list cannot grow.
fn emitQuad(ui: *UiState, tex_in: abi_render_handles.c.ke_texture_handle,
            x0: f32, y0: f32, x1: f32, y1: f32, tu0: f32, tv0: f32, tu1: f32, tv1: f32, color: [4]f32) bool {
    const tex = if (tex_in.bits == abi_render_handles.c.KE_HANDLE_NONE) ui.core.*.white_texture.?(ui.core) else tex_in;
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
    var vbo: abi_asset_resolver.c.ke_gpu_buffer = undefined;
    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_desc{
        .label = "ui.vbo",
        .initial_data = null,
        .size = size,
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_VERTEX | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &vbo));
    if (ui.vbo != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) dev.destroy_buffer.?(dev, ui.vbo);
    ui.vbo = vbo;
    ui.vbo_bytes = size;
}

/// "render.ui.labels", in the render prepare set, with write access to the render world's label
/// component only. Shapes every label against the current backbuffer size, so a resize is picked
/// up on the next frame. It succeeds on every path, including when the view is empty.
fn labelShapeSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const ui = moduleOf(user);

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    if (segc == 0) return R.ok;

    var bw: u32 = 0;
    var bh: u32 = 0;
    ui.core.*.backbuffer_size.?(ui.core, &bw, &bh);

    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const labels: [*c]abi_ui_components.c.ke_label_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            shapeLabel(ui, labels + i, bw, bh);
        }
    }
    return R.ok;
}

/// Records the batches `queueSystem` built into the render pass the graph began over the output.
fn record(user: ?*anyopaque, ctx: ?*rg.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    const ui = moduleOf(user);
    const core = ui.core;
    const rp: [*c]abi_render_gpu.c.ke_gpu_render_pass = @ptrCast(ctx.?.render_pass.?(ctx));
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &ui.pipeline_params));
    ui.binder.bind_render_set.?(ui.binder, rp, ui.frame_set, null, 0);
    rp.*.set_vertex_buffer.?(rp, 0, ui.vbo, 0);
    for (ui.batches.items) |batch| {
        ui.binder.bind_render_set.?(ui.binder, rp, uiSetFor(ui, batch.texture), null, 0);
        rp.*.draw.?(rp, batch.vertex_count, 1, batch.first_vertex, 0);
    }
    return R.ok;
}

/// "render.ui", in the render queue set, reading the render world's quads and labels. Quads with no
/// area are skipped and glyphs are drawn in the premultiplied label color. With nothing emitted, or
/// no frame being declared, it declares nothing; otherwise it uploads the projection (flipped on Y
/// when the ndc convention asks) and the vertices, and declares at KE_RENDER_STAGE_OVERLAY the pass
/// drawing each batch over the frame's output with its texture's set. It fails as out of memory
/// when the vertex list cannot grow, with the device's code when the vertex buffer cannot, and with
/// the graph's code when it refuses the pass.
fn queueSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const ui = moduleOf(user);
    const core = ui.core;

    var quad_segc: usize = 0;
    const quad_segs = ctx.?.view.?(ctx, 0, &quad_segc);
    var label_segc: usize = 0;
    const label_segs = ctx.?.view.?(ctx, 1, &label_segc);
    if (quad_segc == 0 and label_segc == 0) return R.ok;
    const frame = ui.frame;
    if (!frame.live.?(frame)) return R.ok;

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
        const labels: [*c]const abi_ui_components.c.ke_label_component = @ptrCast(@alignCast(label_segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < label_segs.?[s].count) : (i += 1) {
            const l = labels[i];
            if (l.glyph_count == 0) continue;

            const font_idx = l.font_handle.bits & abi_render_handles.c.KE_HANDLE_INDEX_MASK;
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
        return R.code(error.OutOfMemory);
    }
    if (ui.vertices.items.len == 0) return R.ok;
    const bytes = std.mem.sliceAsBytes(ui.vertices.items);
    ensureVertexBuffer(ui, bytes.len) catch |err| return R.code(err);

    var bw: u32 = 0;
    var bh: u32 = 0;
    core.*.backbuffer_size.?(core, &bw, &bh);
    var proj = zm.orthographicOffCenterLh(0.0, @floatFromInt(bw), 0.0, @floatFromInt(bh), 0.0, 1.0);
    if (ui.ndc.y_flip) proj[1][1] = -proj[1][1];
    var proj_arr: [16]f32 = undefined;
    zm.storeMat(proj_arr[0..], proj);
    core.*.upload.?(core, ui.frame_uniform, 0, &proj_arr, 64);

    core.*.upload.?(core, ui.vbo, 0, bytes.ptr, bytes.len);

    ui.output = frame.output.?(frame);
    var target = std.mem.zeroes(rg.ke_render_graph_use);
    target.resource = ui.output;
    target.usage = rg.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT;
    target.load = rg.KE_RENDER_GRAPH_LOAD_KEEP;
    var desc = std.mem.zeroes(rg.ke_render_graph_pass_desc);
    desc.name = "render.ui";
    desc.type = rg.KE_RENDER_GRAPH_PASS_RASTER;
    desc.injection_point = abi_render.c.KE_RENDER_STAGE_OVERLAY;
    desc.uses = (&target)[0..1];
    desc.use_count = 1;
    desc.record = record;
    desc.user = ui;
    const graph = frame.graph.?(frame).?;
    var pass: rg.ke_render_graph_pass = 0;
    return graph.add_pass.?(graph, &desc, &pass);
}

/// Called once by `ke_render_ui_create`, before anything is registered. It builds the pipeline in
/// the format of the frame's output, then stops at the first step that fails; what was built before
/// that step stays in the state for `destroyState` to release.
fn setup(ui: *UiState, p: *const abi_render_context.c.ke_render_context) R.Error!void {
    const core: *abi_render.c.ke_render_service = p.service.?;
    const dev: *abi_render_gpu.c.ke_gpu_device = p.device.?;
    ui.core = core;
    ui.device = dev;
    ui.ndc = p.device.?.get_ndc_convention.?(p.device);

    ui.frame = p.frame.?;
    const format = ui.frame.output_format.?(ui.frame);

    var vs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "ui", abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &vs));
    var fs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "ui", abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT, &fs));

    ui.binder = core.*.resource_binder.?(core).?;
    try R.check(ui.binder.create_shader_layout.?(ui.binder, &shader_layout, &ui.layout));

    const attrs = [_]abi_render_gpu.c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = @offsetOf(UiVertex, "position") },
        .{ .shader_location = 1, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = @offsetOf(UiVertex, "uv") },
        .{ .shader_location = 2, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X4, .offset = @offsetOf(UiVertex, "color") },
    };
    const vbl = abi_render_gpu.c.ke_gpu_vertex_buffer_layout{
        .stride = @sizeOf(UiVertex),
        .step_mode = abi_render_gpu.c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 3,
        .attributes = &attrs,
    };

    var pp = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_desc);
    pp.label = "ui.pipeline";
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = abi_render_gpu.c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = abi_render_gpu.c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = abi_render_gpu.c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = (&vbl)[0..1];
    try R.check(ui.binder.pipeline_layouts.?(ui.binder, ui.layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count));
    pp.blend_state.blend_enabled = true;
    pp.blend_state.src_color = abi_render_gpu.c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_color = abi_render_gpu.c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.color_op = abi_render_gpu.c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.src_alpha = abi_render_gpu.c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_alpha = abi_render_gpu.c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.alpha_op = abi_render_gpu.c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = false;
    pp.depth_stencil.depth_write_enabled = false;
    pp.depth_stencil.depth_compare = abi_render_gpu.c.KE_GPU_COMPARE_ALWAYS;
    pp.color_target_formats[0] = format;
    pp.color_target_count = 1;

    ui.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &ui.pipeline_params) == abi_render_gpu.c.KE_GPU_INVALID_HANDLE) {
        log.warn("ui pass: render pipeline creation failed", .{});
        return error.NotInitialized;
    }

    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_desc{
        .label = "ui.frame_uniform",
        .initial_data = null,
        .size = 64,
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_UNIFORM | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &ui.frame_uniform));

    const frame_binding = [_]abi_render_gpu.c.ke_render_shader_binding{
        .{ .name = "frame", .buffer = ui.frame_uniform, .buffer_offset = 0, .buffer_size = 64, .texture_view = 0, .sampler = 0 },
    };
    try R.check(ui.binder.create_set.?(ui.binder, ui.layout, null, "ui.frame_set", &frame_binding, frame_binding.len, &ui.frame_set));

    try ensureVertexBuffer(ui, 6 * @sizeOf(UiVertex));

    ui.access = .{.{ .component = ui.frame.frame_cid.?(ui.frame), .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
}

/// Safe on a partly built state: each GPU object, set and layout is released only if `setup` had
/// created it.
fn destroyState(ui: *UiState) void {
    const dev = ui.device;
    const invalid = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    if (ui.frame_uniform != invalid) dev.destroy_buffer.?(dev, ui.frame_uniform);
    if (ui.vbo != invalid) dev.destroy_buffer.?(dev, ui.vbo);
    if (ui.layout != abi_render_gpu.c.KE_RENDER_BINDING_INVALID) {
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

/// Slot `attach` of the module: "render.ui.labels" in the render prepare set and "render.ui" in the
/// render queue set, removing the first when the second is refused.
fn attach(self: ?*abi_module.c.ke_module, targets_in: ?*const abi_module.c.ke_module_targets) callconv(.c) abi_result.c.ke_result {
    const ui: *UiState = @ptrCast(@alignCast((self orelse return R.code(error.InvalidArgument)).handle));
    const targets = targets_in orelse return R.code(error.InvalidArgument);
    if (ui.schedule != null) return R.code(error.NotSupported);
    const schedule: *abi_schedule.c.ke_schedule = @ptrCast(targets.render orelse return R.code(error.InvalidArgument));
    ui.sets = .{ targets.render_prepare_set, targets.render_queue_set };
    const shape: abi_schedule.c.ke_schedule_system_desc = .{
        .name = "render.ui.labels",
        .user_data = ui,
        .execute = labelShapeSystem,
        .queries = &ui.label_shape_queries,
        .query_count = ui.label_shape_queries.len,
        .sets = ui.sets[0..].ptr,
        .set_count = 1,
    };
    const shaped = schedule.register_system.?(schedule, &shape, &ui.systems[0]);
    if (shaped != R.ok) return shaped;
    const draw: abi_schedule.c.ke_schedule_system_desc = .{
        .name = "render.ui",
        .user_data = ui,
        .execute = queueSystem,
        .queries = &ui.queries,
        .query_count = ui.queries.len,
        .access = &ui.access,
        .access_count = ui.access.len,
        .sets = ui.sets[1..].ptr,
        .set_count = 1,
    };
    const drawn = schedule.register_system.?(schedule, &draw, &ui.systems[1]);
    if (drawn != R.ok) {
        _ = schedule.unregister_system.?(schedule, ui.systems[0]);
        return drawn;
    }
    ui.schedule = schedule;
    return R.ok;
}

/// Slot `detach` of the module.
fn detach(self: ?*abi_module.c.ke_module) callconv(.c) void {
    const ui: *UiState = @ptrCast(@alignCast((self orelse return).handle));
    const schedule = ui.schedule orelse return;
    for (ui.systems) |id| _ = schedule.unregister_system.?(schedule, id);
    ui.schedule = null;
}

fn destroyModule(self: ?*abi_module.c.ke_module) callconv(.c) void {
    detach(self);
}

/// The destroy slot of the handle that `ke_render_ui_create` returns.
fn destroyHandle(self: ?*abi_render_ui.c.ke_render_ui) callconv(.c) void {
    const ui = stateOf(self orelse return);
    detach(&ui.module);
    destroyState(ui);
    gpa.destroy(ui);
}

/// A missing ecs, main world, extraction, service, device or frame fails as an invalid argument and
/// a state that cannot be allocated as out of memory. On success it has registered the quad and
/// label components in both worlds, a copy of each in the extraction, and the quad as synced. A
/// failing `setup` or registration fails with its code and leaves the handle zeroed. On success the
/// returned handle owns the state until its destroy slot runs.
export fn ke_render_ui_create(context_in: ?*const abi_render_context.c.ke_render_context, out_ui: ?*abi_render_ui.c.ke_render_ui_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_ui orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = context_in orelse return R.code(error.InvalidArgument);
    if (p.ecs == null or p.main == null or p.extraction == null or p.frame == null or p.service == null or p.device == null) return R.code(error.InvalidArgument);

    const ui = gpa.create(UiState) catch |err| return R.code(err);
    ui.* = .{};
    ui.api = .{ .handle = ui, .load_font = uiLoadFont };
    ui.module = .{ .handle = ui, .attach = attach, .detach = detach };
    register(ui, p) catch |err| {
        destroyState(ui);
        gpa.destroy(ui);
        return R.code(err);
    };
    out.* = .{ .ref = @ptrCast(&ui.api), .destroy = destroyHandle };
    return R.ok;
}

fn registerUi(e: *abi_ecs.c.ke_ecs, quad: *abi_asset_resolver.c.ke_component_id, label: *abi_asset_resolver.c.ke_component_id) R.Error!void {
    quad.* = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.c.ke_component_desc{ .name = abi_ui_components.c.KE_COMPONENT_NAME_UI_QUAD, .size = @sizeOf(UiQuadComponent), .alignment = @alignOf(UiQuadComponent), .fields = &abi_render_contract.c.ke_ui_quad_component_fields, .field_count = abi_render_contract.c.ke_ui_quad_component_fields.len }, quad));
    label.* = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.c.ke_component_desc{ .name = abi_ui_components.c.KE_COMPONENT_NAME_LABEL, .size = @sizeOf(abi_ui_components.c.ke_label_component), .alignment = @alignOf(abi_ui_components.c.ke_label_component), .fields = &abi_render_contract.c.ke_label_component_fields, .field_count = abi_render_contract.c.ke_label_component_fields.len }, label));
}

fn register(ui: *UiState, p: *const abi_render_context.c.ke_render_context) R.Error!void {
    try setup(ui, p);

    var main_quad: abi_asset_resolver.c.ke_component_id = 0;
    var main_label: abi_asset_resolver.c.ke_component_id = 0;
    try registerUi(p.main.?, &main_quad, &main_label);
    try registerUi(p.ecs.?, &ui.quad_cid, &ui.label_cid);
    const extraction = p.extraction.?;
    try R.check(extraction.extract_copy.?(extraction, main_quad, ui.quad_cid));
    try R.check(extraction.extract_copy.?(extraction, main_label, ui.label_cid));
    try R.check(extraction.sync_component.?(extraction, main_quad));
    try R.check(extraction.sync_component.?(extraction, main_label));

    const rd = abi_ecs.c.KE_ECS_ACCESS_READ;
    ui.queries_terms = .{ .{ .component = ui.quad_cid, .access = rd }, .{ .component = ui.label_cid, .access = rd } };
    ui.queries = .{ .{ .terms = ui.queries_terms[0..].ptr, .term_count = 1 }, .{ .terms = ui.queries_terms[1..].ptr, .term_count = 1 } };
    ui.label_shape_queries_terms = .{.{ .component = ui.label_cid, .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
    ui.label_shape_queries = .{.{ .terms = ui.label_shape_queries_terms[0..].ptr, .term_count = 1 }};
}

/// The factory declared in ui_systems_create.h: the module is a view of the pass, destroyed with
/// it or on its own.
export fn ke_render_ui_systems_create(ui_in: ?*abi_render_ui.c.ke_render_ui, out_module: ?*abi_module.c.ke_module_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_module.c.ke_module_handle);
    const ui = stateOf(ui_in orelse return R.code(error.InvalidArgument));
    out.* = .{ .ref = &ui.module, .destroy = destroyModule };
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");

fn quadView(_: ?*abi_schedule.c.ke_schedule_ctx, index: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    if (index != 0) {
        out_count.?.* = 0;
        return null;
    }
    out_count.?.* = 1;
    return (&quad_segment)[0..1];
}

var test_quad = std.mem.zeroInit(UiQuadComponent, .{ .dst_w = 10, .dst_h = 10, .color = .{ 1, 1, 1, 1 } });
var quad_columns = [_]?*anyopaque{@ptrCast(&test_quad)};
var quad_segment: abi_ecs.c.ke_ecs_segment = .{ .entities = null, .count = 1, .columns = &quad_columns, .column_count = 1 };
var quad_ctx: abi_schedule.c.ke_schedule_ctx = .{ .handle = null, .commands = null, .view = quadView, .slice = null };

/// The parts a ui pass is made of in a test.
const Rig = struct {
    dev: zsub.For(abi_render_gpu.c.ke_gpu_device),
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    core: zsub.For(abi_render.c.ke_render_service),
    schedule: zsub.For(abi_schedule.c.ke_schedule),
    main: zsub.For(abi_ecs.c.ke_ecs),
    render: zsub.For(abi_ecs.c.ke_ecs),
    extraction: zsub.For(abi_extraction.c.ke_extraction),
    frame: zsub.For(abi_render_frame.c.ke_render_frame),
    graph: zsub.For(rg.ke_render_graph),

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
        _ = self.core.when(.texture_view).returnsFresh();
        _ = self.core.when(.white_texture).returns(.{ .bits = 1 });
        try self.schedule.init();
        _ = self.schedule.when(.register_system).writesFresh(2);
        try self.main.init();
        _ = self.main.when(.component_register).writesFresh(2);
        try self.render.init();
        _ = self.render.when(.component_register).writesFresh(2);
        try self.extraction.init();
        try self.graph.init();
        try self.frame.init();
        _ = self.frame.when(.frame_cid).returns(11);
        _ = self.frame.when(.live).returns(true);
        _ = self.frame.when(.output).returns(3);
        _ = self.frame.when(.graph).returns(self.graph.api());
        _ = self.frame.when(.output_format).returns(abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM);
    }

    fn deinit(self: *Rig) void {
        self.frame.deinit();
        self.graph.deinit();
        self.extraction.deinit();
        self.render.deinit();
        self.main.deinit();
        self.schedule.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn context(self: *Rig) abi_render_context.c.ke_render_context {
        return std.mem.zeroInit(abi_render_context.c.ke_render_context, .{ .ecs = self.render.api(), .main = self.main.api(), .extraction = self.extraction.api(), .frame = self.frame.api(), .service = self.core.api(), .device = self.dev.api() });
    }

    fn ui(self: *Rig) !abi_render_ui.c.ke_render_ui_handle {
        var h: abi_render_ui.c.ke_render_ui_handle = undefined;
        const p = self.context();
        try R.check(ke_render_ui_create(&p, &h));
        return h;
    }

    fn targets(self: *Rig) abi_module.c.ke_module_targets {
        var t = std.mem.zeroes(abi_module.c.ke_module_targets);
        t.render = @ptrCast(self.schedule.api());
        return t;
    }

    fn expectReleased(self: *Rig) !void {
        try self.dev.received(.destroy_buffer).where(zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_buffer));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

test "the ui pass registers its components in both worlds, copies them into the render world, and leaves nothing live once destroyed" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.ui();
    try rig.main.received(.component_register).times(2);
    try rig.render.received(.component_register).times(2);
    try rig.extraction.received(.extract_copy).times(2);
    try rig.extraction.received(.sync_component).times(2);
    h.destroy.?(h.ref);
    try rig.expectReleased();
}

test "the ui module attaches its label and draw systems to the render prepare and queue sets, and detaching removes them" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.ui();
    defer h.destroy.?(h.ref);
    var m: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_ui_systems_create(h.ref, &m));
    const t = rig.targets();
    try R.check(m.ref.?.attach.?(m.ref, &t));
    try rig.schedule.received(.register_system).times(2);
    m.destroy.?(m.ref);
    try rig.schedule.received(.unregister_system).sameAs(rig.schedule.received(.register_system));
}

test "a ui module whose draw system the schedule refuses takes its label system back" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.schedule.when(.register_system).returnsSeq(&.{ abi_result.c.KE_OK, abi_result.c.KE_RESULT_OUT_OF_MEMORY });
    const h = try rig.ui();
    defer h.destroy.?(h.ref);
    var m: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_ui_systems_create(h.ref, &m));
    const t = rig.targets();
    try testing.expect(m.ref.?.attach.?(m.ref, &t) != R.ok);
    try rig.schedule.received(.unregister_system).times(1);
}

test "a visible quad is drawn by a pass declared over the frame's output at the overlay stage" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.ui();
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, queueSystem(&quad_ctx, stateOf(h.ref), 0));
    try rig.graph.received(.add_pass).times(1);
    try rig.core.received(.upload).atLeast(2);
}

test "a frame not being declared gets no ui pass" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.frame.when(.live).returns(false);
    const h = try rig.ui();
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, queueSystem(&quad_ctx, stateOf(h.ref), 0));
    try rig.graph.received(.add_pass).never();
}

test "a ui pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.c.KE_RESULT_GENERAL);
    var h: abi_render_ui.c.ke_render_ui_handle = undefined;
    const p = rig.context();
    try testing.expect(ke_render_ui_create(&p, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
}

test "a ui pass missing its frame is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var p = rig.context();
    p.frame = null;
    var h: abi_render_ui.c.ke_render_ui_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_ui_create(&p, &h)));
}

test "creating and destroying ui passes leaves no block allocated" {
    try heap.expectNoLeaks();
}
