//! The UI pass: draws the entities carrying a UI quad component or a label component as
//! alpha-blended textured triangles over the backbuffer, and shapes labels from registered fonts.
//! It also owns the creation and teardown of that pass, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const c = @import("c");
const handles = @import("handle").Handles(c);

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
    texture: c.ke_texture_handle,
    first_vertex: u32,
    vertex_count: u32,
};

const UiQuadComponent = c.ke_ui_quad_component;

/// One entry of `fonts`. `key` and `glyphs` are copies owned by the state and freed by
/// `destroyState`. `atlas` is stored as the caller gave it and is not owned here.
const UiFont = struct {
    key: []u8 = &.{},
    atlas: c.ke_texture_handle = undefined,
    glyphs: []c.ke_glyph_metrics = &.{},
    line_height: f32 = 0,
    ascent: f32 = 0,
    in_use: bool = false,
};

/// Everything the pass owns. It is allocated by `ke_render_ui_create` and freed by `destroyHandle`,
/// or by the create itself when it fails. The handle's reference is `api`, whose `handle` points
/// back at the state. `io` and `access` are filled once by `setup`. The query declarations are filled by
/// the create and passed to the registrations by address. `vertices` and `batches` are rewritten by
/// `system` on every frame.
const UiState = struct {
    api: c.ke_render_ui = undefined,

    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    ndc: c.ke_ndc_convention = undefined,
    input: ?[:0]u8 = null,
    output: ?[:0]u8 = null,

    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    binder: *c.ke_render_resource_binder = undefined,
    layout: c.ke_render_shader_layout = c.KE_RENDER_BINDING_INVALID,
    frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    frame_set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID,
    vbo: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    vbo_bytes: usize = 0,

    vertices: std.ArrayList(UiVertex) = .empty,
    batches: std.ArrayList(UiBatch) = .empty,
    set_cache: std.AutoHashMapUnmanaged(u32, c.ke_render_resource_set) = .empty,

    fonts: std.ArrayList(UiFont) = .empty,

    writes: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    reads: [1][*c]const u8 = undefined,
    access: [2]c.ke_component_access = undefined,
    access_count: u32 = 0,
    queries_terms: [2]c.ke_component_access = undefined,
    queries: [2]c.ke_query_decl = undefined,
    quad_cid: c.ke_component_id = 0,
    label_cid: c.ke_component_id = 0,
    label_shape_queries_terms: [1]c.ke_component_access = undefined,
    label_shape_queries: [1]c.ke_query_decl = undefined,
};

/// Recovers the state from the `handle` of its `api` field, which points back at it.
fn stateOf(self: [*c]c.ke_render_ui) *UiState {
    return @ptrCast(@alignCast(self.*.handle));
}

/// Called through the `load_font` slot. A key already in use returns that font's handle, and the
/// glyph table given with the call is not copied again. The copies made here are released by
/// `destroyState`.
fn uiLoadFont(self: [*c]c.ke_render_ui, key: [*c]const u8, atlas: c.ke_texture_handle,
              glyphs: [*c]const c.ke_glyph_metrics, glyph_count: u32,
              line_height: f32, ascent: f32, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_ui_font_handle {
    const ui = stateOf(self);
    const key_slice = std.mem.span(key);

    for (ui.fonts.items, 0..) |f, i| {
        if (f.in_use and std.mem.eql(u8, f.key, key_slice))
            return .{ .bits = handles.make(@intCast(i), c.KE_HANDLE_GENERATION_FIRST) };
    }

    var slot: ?usize = null;
    for (ui.fonts.items, 0..) |f, i| {
        if (!f.in_use) { slot = i; break; }
    }
    const idx = slot orelse blk: {
        ui.fonts.append(gpa, .{}) catch {
            c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "ui text: font table allocation failed", @src().file, @intCast(@src().line), null);
            return c.KE_UI_FONT_NONE;
        };
        break :blk ui.fonts.items.len - 1;
    };

    const owned_key = gpa.dupe(u8, key_slice) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "ui text: font key alloc failed", @src().file, @intCast(@src().line), null);
        return c.KE_UI_FONT_NONE;
    };
    const owned_glyphs = gpa.dupe(c.ke_glyph_metrics, glyphs[0..glyph_count]) catch {
        gpa.free(owned_key);
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "ui text: glyph table alloc failed", @src().file, @intCast(@src().line), null);
        return c.KE_UI_FONT_NONE;
    };

    ui.fonts.items[idx] = .{
        .key = owned_key,
        .atlas = atlas,
        .glyphs = owned_glyphs,
        .line_height = line_height,
        .ascent = ascent,
        .in_use = true,
    };
    return .{ .bits = handles.make(@intCast(idx), c.KE_HANDLE_GENERATION_FIRST) };
}

fn findGlyph(glyphs: []const c.ke_glyph_metrics, codepoint: u32) ?c.ke_glyph_metrics {
    for (glyphs) |g| {
        if (g.codepoint == codepoint) return g;
    }
    return null;
}

/// Called by `labelShapeSystem` for each label. It writes the glyph quads into the label component
/// itself: when it returns, `glyph_count` is the number of those quads that `system` will draw.
fn shapeLabel(ui: *UiState, l_ptr: [*c]c.ke_label_component, bb_w: u32, bb_h: u32) void {
    const l: *c.ke_label_component = @ptrCast(l_ptr);
    l.glyph_count = 0;

    const font_idx = handles.index(l.font_handle.bits);
    if (l.font_handle.bits == c.KE_HANDLE_NONE or font_idx >= ui.fonts.items.len or !ui.fonts.items[font_idx].in_use)
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
        if (slot >= c.KE_LABEL_MAX_GLYPHS) break;
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

const shader_layout = c.ke_render_shader_layout_params{
    .shader = "ui",
    .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = null,
    .hint_count = 0,
};

/// Called by `system` for each batch, with the set of a texture built on first use and cached by
/// the texture's index. Creation passes no error output, so an invalid set is not kept, and the
/// next draw of that slot creates it again.
fn uiSetFor(ui: *UiState, tex: c.ke_texture_handle) c.ke_render_resource_set {
    if (ui.set_cache.get(tex.bits)) |cached| return cached;

    const view = ui.core.*.texture_view.?(ui.core, tex);
    const bindings = [_]c.ke_render_shader_binding{
        .{ .name = "t_tex", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = view, .sampler = 0 },
    };
    const set = ui.binder.create_set.?(ui.binder, ui.layout, "tex", "ui.tex_set", &bindings, bindings.len, null);
    if (set == c.KE_RENDER_BINDING_INVALID) return set;
    ui.set_cache.put(gpa, tex.bits, set) catch {
        ui.binder.destroy_set.?(ui.binder, set);
        return c.KE_RENDER_BINDING_INVALID;
    };
    return set;
}

/// The user pointer both systems receive is the `UiState` itself, set by `ke_render_ui_create`.
inline fn moduleOf(user: ?*anyopaque) *UiState {
    return @alignCast(@ptrCast(user.?));
}

/// Called by `system` for each quad and each glyph. A null texture is drawn with the white texture.
/// Returns false when the vertex or batch list cannot grow.
fn emitQuad(ui: *UiState, tex_in: c.ke_texture_handle,
            x0: f32, y0: f32, x1: f32, y1: f32, tu0: f32, tv0: f32, tu1: f32, tv1: f32, color: [4]f32) bool {
    const tex = if (tex_in.bits == c.KE_HANDLE_NONE) ui.core.*.white_texture.?(ui.core) else tex_in;
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
/// it is smaller.
fn ensureVertexBuffer(ui: *UiState, bytes: usize, out_error: [*c][*c]c.ke_error) bool {
    if (bytes <= ui.vbo_bytes) return true;
    const size = std.math.ceilPowerOfTwoAssert(usize, bytes);
    const dev = ui.device;
    const vbo = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .label = "ui.vbo",
        .initial_data = null,
        .size = size,
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, out_error);
    if (vbo == c.KE_GPU_INVALID_HANDLE) return false;
    if (ui.vbo != c.KE_GPU_INVALID_HANDLE) dev.destroy_buffer.?(dev, ui.vbo);
    ui.vbo = vbo;
    ui.vbo_bytes = size;
    return true;
}

/// Registered by `ke_render_ui_create` for the update phase, with write access to the label
/// component only. Shapes every label against the current backbuffer size, so a resize is picked
/// up on the next frame. It returns true on every path, including when the view is empty.
fn labelShapeSystem(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const ui = moduleOf(user);

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    if (segc == 0) return true;

    var bw: u32 = 0;
    var bh: u32 = 0;
    ui.core.*.backbuffer_size.?(ui.core, &bw, &bh);

    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const labels: [*c]c.ke_label_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            shapeLabel(ui, labels + i, bw, bh);
        }
    }
    return true;
}

/// Registered by `ke_render_ui_create` for the render phase, reading quads and labels. Quads with
/// no area are skipped and glyphs are drawn in the premultiplied label color. With nothing emitted
/// the render pass is opened and ended without drawing, so the output still starts as the input;
/// otherwise the projection (flipped on Y when the ndc convention
/// asks) and the vertices are uploaded and each batch is drawn with its texture's set. It
/// returns true on every path, including when the render service yields no pass to draw into.
fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const ui = moduleOf(user);
    const core = ui.core;

    var quad_segc: usize = 0;
    const quad_segs = ctx.?.view.?(ctx, 0, &quad_segc);
    var label_segc: usize = 0;
    const label_segs = ctx.?.view.?(ctx, 1, &label_segc);

    const pc = core.*.begin_pass.?(core, &ui.io);
    if (pc == null) return true;

    ui.vertices.clearRetainingCapacity();
    ui.batches.clearRetainingCapacity();
    var emitted = true;

    var s: usize = 0;
    while (emitted and s < quad_segc) : (s += 1) {
        const quads: [*c]const UiQuadComponent = @ptrCast(@alignCast(quad_segs[s].columns[0]));
        var i: usize = 0;
        while (i < quad_segs[s].count) : (i += 1) {
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
        const labels: [*c]const c.ke_label_component = @ptrCast(@alignCast(label_segs[s].columns[0]));
        var i: usize = 0;
        while (i < label_segs[s].count) : (i += 1) {
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
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "ui pass: vertex list allocation failed", @src().file, @intCast(@src().line), null);
        core.*.end_pass.?(core, pc);
        return false;
    }
    if (ui.vertices.items.len == 0) {
        const empty_rp = pc.*.begin_render.?(pc);
        empty_rp.*.end.?(empty_rp);
        core.*.end_pass.?(core, pc);
        return true;
    }
    const bytes = std.mem.sliceAsBytes(ui.vertices.items);
    if (!ensureVertexBuffer(ui, bytes.len, out_error)) {
        core.*.end_pass.?(core, pc);
        return false;
    }

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    var proj = zm.orthographicOffCenterLh(0.0, @floatFromInt(bw), 0.0, @floatFromInt(bh), 0.0, 1.0);
    if (ui.ndc.y_flip) proj[1][1] = -proj[1][1];
    var proj_arr: [16]f32 = undefined;
    zm.storeMat(proj_arr[0..], proj);
    core.*.upload.?(core, ui.frame_uniform, 0, &proj_arr, 64);

    core.*.upload.?(core, ui.vbo, 0, bytes.ptr, bytes.len);

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &ui.pipeline_params));
    ui.binder.bind_render_set.?(ui.binder, rp, ui.frame_set, null, 0);
    rp.*.set_vertex_buffer.?(rp, 0, ui.vbo, 0);

    for (ui.batches.items) |batch| {
        ui.binder.bind_render_set.?(ui.binder, rp, uiSetFor(ui, batch.texture), null, 0);
        rp.*.draw.?(rp, batch.vertex_count, 1, batch.first_vertex, 0);
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return true;
}

/// Called once by `ke_render_ui_create`, before anything is registered. It copies the names and
/// declares the output when the service has none of that name, then stops at the first step that
/// fails and returns false; what was built before that step stays in the state for `destroyState`
/// to release. On success `io` and `access` describe the pass that `system` begins and the write it
/// makes.
fn setup(ui: *UiState, p: *const c.ke_render_ui_params, out_error: [*c][*c]c.ke_error) bool {
    const core: *c.ke_render_service = p.service;
    const dev: *c.ke_gpu_device = p.device;
    ui.core = core;
    ui.device = dev;
    ui.ndc = p.ndc;

    if (p.input != null) ui.input = gpa.dupeZ(u8, std.mem.span(p.input)) catch return outOfMemory(out_error);
    ui.output = gpa.dupeZ(u8, std.mem.span(p.output)) catch return outOfMemory(out_error);
    var format = core.*.resource_format.?(core, ui.output.?.ptr);
    if (format == c.KE_GPU_TEXTURE_FORMAT_INVALID) {
        format = core.*.backbuffer_format.?(core);
        if (core.*.declare.?(core, &c.ke_render_resource_params{
            .name = ui.output.?.ptr,
            .type = c.KE_RENDER_RESOURCE_TEXTURE,
            .format = format,
            .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
            .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
        }, out_error) == c.KE_COMPONENT_INVALID) return false;
    }

    const vs = core.*.load_shader.?(core, "ui", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    const fs = core.*.load_shader.?(core, "ui", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;

    ui.binder = core.*.resource_binder.?(core);
    ui.layout = ui.binder.create_shader_layout.?(ui.binder, &shader_layout, out_error);
    if (ui.layout == c.KE_RENDER_BINDING_INVALID) return false;

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
    pp.label = "ui.pipeline";
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = &vbl;
    if (!ui.binder.pipeline_layouts.?(ui.binder, ui.layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count, out_error)) return false;
    pp.blend_state.blend_enabled = true;
    pp.blend_state.src_color = c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_color = c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.color_op = c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.src_alpha = c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_alpha = c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.alpha_op = c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = false;
    pp.depth_stencil.depth_write_enabled = false;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    pp.color_target_formats[0] = format;
    pp.color_target_count = 1;

    ui.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &ui.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "ui pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    ui.frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .label = "ui.frame_uniform",
        .initial_data = null,
        .size = 64,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, out_error);
    if (ui.frame_uniform == c.KE_GPU_INVALID_HANDLE) return false;

    const frame_binding = [_]c.ke_render_shader_binding{
        .{ .name = "frame", .buffer = ui.frame_uniform, .buffer_offset = 0, .buffer_size = 64, .texture_view = 0, .sampler = 0 },
    };
    ui.frame_set = ui.binder.create_set.?(ui.binder, ui.layout, null, "ui.frame_set", &frame_binding, frame_binding.len, out_error);
    if (ui.frame_set == c.KE_RENDER_BINDING_INVALID) return false;

    if (!ensureVertexBuffer(ui, 6 * @sizeOf(UiVertex), out_error)) return false;


    ui.writes = .{ui.output.?.ptr};
    ui.io = std.mem.zeroes(c.ke_render_pass_io);
    ui.io.name = "render.ui";
    ui.io.writes = @ptrCast(&ui.writes);
    ui.io.writes_count = 1;
    ui.access[0] = .{ .cid = core.*.cid.?(core, ui.output.?.ptr), .access = c.KE_ACCESS_WRITE };
    ui.access_count = 1;
    if (ui.input != null) {
        ui.reads = .{ui.input.?.ptr};
        ui.io.reads = @ptrCast(&ui.reads);
        ui.io.reads_count = 1;
        ui.io.load_from = ui.input.?.ptr;
        ui.access[1] = .{ .cid = core.*.cid.?(core, ui.input.?.ptr), .access = c.KE_ACCESS_READ };
        ui.access_count = 2;
    }
    return true;
}

fn outOfMemory(out_error: [*c][*c]c.ke_error) bool {
    c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "ui pass: name allocation failed", @src().file, @intCast(@src().line), null);
    return false;
}

/// Safe on a partly built state: each GPU object, set and layout is released only if `setup` had
/// created it.
fn destroyState(ui: *UiState) void {
    if (ui.input) |name| gpa.free(name);
    if (ui.output) |name| gpa.free(name);
    const dev = ui.device;
    const invalid = c.KE_GPU_INVALID_HANDLE;
    if (ui.frame_uniform != invalid) dev.destroy_buffer.?(dev, ui.frame_uniform);
    if (ui.vbo != invalid) dev.destroy_buffer.?(dev, ui.vbo);
    if (ui.layout != c.KE_RENDER_BINDING_INVALID) {
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
fn destroyHandle(self: ?*c.ke_render_ui) callconv(.c) void {
    const ui = stateOf(self orelse return);
    destroyState(ui);
    gpa.destroy(ui);
}

/// A missing runtime, ecs, service, device or output fails as an invalid argument and a state that
/// cannot be allocated as out of memory. On success it has registered the quad and label components
/// with the ecs and two systems with the runtime: `labelShapeSystem` in the update phase and
/// `system` in the render phase. A failing `setup` or a refused system registration passes the
/// error through the out error of the call that failed, and a refused second registration takes the
/// first back. On success the returned handle owns the state until its destroy slot runs.
export fn ke_render_ui_create(params_in: ?*const c.ke_render_ui_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_ui_handle {
    const empty = c.ke_render_ui_handle{ .ref = null, .destroy = null };
    const p = params_in orelse return refused(out_error);
    const rt: *c.ke_runtime = p.runtime orelse return refused(out_error);
    const e: *c.ke_ecs = p.ecs orelse return refused(out_error);
    if (p.service == null or p.device == null or p.output == null) return refused(out_error);

    const ui = gpa.create(UiState) catch {
        _ = outOfMemory(out_error);
        return empty;
    };
    ui.* = .{};
    ui.api = .{ .handle = ui, .load_font = uiLoadFont };
    if (!setup(ui, p, out_error)) {
        destroyState(ui);
        gpa.destroy(ui);
        return empty;
    }

    ui.quad_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_UI_QUAD, @sizeOf(UiQuadComponent), &c.ke_ui_quad_component_fields, c.ke_ui_quad_component_fields.len, null);

    ui.label_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_LABEL, @sizeOf(c.ke_label_component), &c.ke_label_component_fields, c.ke_label_component_fields.len, null);
    ui.queries_terms = .{ .{ .cid = ui.quad_cid, .access = c.KE_ACCESS_READ }, .{ .cid = ui.label_cid, .access = c.KE_ACCESS_READ } };
    ui.queries = .{ .{ .terms = &ui.queries_terms[0], .term_count = 1 }, .{ .terms = &ui.queries_terms[1], .term_count = 1 } };

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.ui";
    params.phase = c.KE_PHASE_RENDER;
    params.queries = &ui.queries;
    params.query_count = ui.queries.len;
    params.access_list = &ui.access;
    params.access_count = ui.access_count;
    params.pinned_thread = 0;
    params.user_data = ui;
    params.execute = system;
    const first_system = rt.register_system.?(rt, &params, out_error);
    if (first_system == 0) {
        destroyState(ui);
        gpa.destroy(ui);
        return empty;
    }

    ui.label_shape_queries_terms = .{ .{ .cid = ui.label_cid, .access = c.KE_ACCESS_WRITE } };
    ui.label_shape_queries = .{ .{ .terms = &ui.label_shape_queries_terms[0], .term_count = 1 } };

    var shape_params = std.mem.zeroes(c.ke_runtime_system_params);
    shape_params.name = "render.ui.labels";
    shape_params.phase = c.KE_PHASE_UPDATE;
    shape_params.queries = &ui.label_shape_queries;
    shape_params.query_count = ui.label_shape_queries.len;
    shape_params.pinned_thread = 0;
    shape_params.user_data = ui;
    shape_params.execute = labelShapeSystem;
    if (rt.register_system.?(rt, &shape_params, out_error) == 0) {
        _ = rt.unregister_system.?(rt, first_system, null);
        destroyState(ui);
        gpa.destroy(ui);
        return empty;
    }

    return .{ .ref = @ptrCast(&ui.api), .destroy = destroyHandle };
}

fn refused(out_error: [*c][*c]c.ke_error) c.ke_render_ui_handle {
    c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "ui pass: runtime, ecs, service, device and output are required", @src().file, @intCast(@src().line), null);
    return .{ .ref = null, .destroy = null };
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the ui pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    const h = ke_render_ui_create(&.{ .runtime = rt.api(), .ecs = ecs.api(), .service = core.api(), .device = dev.api(), .ndc = std.mem.zeroes(c.ke_ndc_convention), .input = "ldr", .output = "backbuffer" }, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a ui pass whose shader fails to load releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    core.shader_loads_fail = true;
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    const h = ke_render_ui_create(&.{ .runtime = rt.api(), .ecs = ecs.api(), .service = core.api(), .device = dev.api(), .ndc = std.mem.zeroes(c.ke_ndc_convention), .input = "ldr", .output = "backbuffer" }, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a ui pass the runtime refuses to register releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    rt.limit = 0;
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    const h = ke_render_ui_create(&.{ .runtime = rt.api(), .ecs = ecs.api(), .service = core.api(), .device = dev.api(), .ndc = std.mem.zeroes(c.ke_ndc_convention), .input = "ldr", .output = "backbuffer" }, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a ui pass the runtime refuses its second system takes the first one back" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    rt.limit = 1;
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    const h = ke_render_ui_create(&.{ .runtime = rt.api(), .ecs = ecs.api(), .service = core.api(), .device = dev.api(), .ndc = std.mem.zeroes(c.ke_ndc_convention), .input = "ldr", .output = "backbuffer" }, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(u32, 0), rt.live_count);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
