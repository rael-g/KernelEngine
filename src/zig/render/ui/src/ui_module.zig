const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;
const handles = @import("handle").Handles(c);

const heap = @import("heap");
const gpa = heap.gpa;

const MAX_UI_QUADS = 8192;
const MAX_UI_BATCHES = 512;
const MAX_UI_TEXTURES = 256;
const MAX_UI_FONTS = 64;

const UiVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
};
const UiBatch = struct {
    texture: c.ke_texture_handle,
    first_vertex: u32,
    vertex_count: u32,
};

const UiQuadComponent = c.ke_ui_quad_component;

const UiFont = struct {
    key: []u8 = &.{},
    atlas: c.ke_texture_handle = undefined,
    glyphs: []c.ke_glyph_metrics = &.{},
    line_height: f32 = 0,
    ascent: f32 = 0,
    in_use: bool = false,
};

const UiState = struct {
    api: c.ke_render_ui = undefined,

    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    ndc: c.ke_ndc_convention = undefined,

    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    bgl_frame: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    bgl_tex: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    frame_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    vbo: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    vertices: [MAX_UI_QUADS * 6]UiVertex = undefined,
    batches: [MAX_UI_BATCHES]UiBatch = undefined,
    bind_group_cache: [MAX_UI_TEXTURES]c.ke_gpu_bind_group = undefined,

    fonts: [MAX_UI_FONTS]UiFont = undefined,

    writes: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [1]c.ke_component_access = undefined,
    queries: [2]c.ke_query_decl = undefined,
    quad_cid: c.ke_component_id = 0,
    label_cid: c.ke_component_id = 0,
    label_shape_queries: [1]c.ke_query_decl = undefined,
};

fn stateOf(self: [*c]c.ke_render_ui) *UiState {
    return @alignCast(@ptrCast(self));
}

fn uiLoadFont(self: [*c]c.ke_render_ui, key: [*c]const u8, atlas: c.ke_texture_handle,
              glyphs: [*c]const c.ke_glyph_metrics, glyph_count: u32,
              line_height: f32, ascent: f32, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_ui_font_handle {
    const ui = stateOf(self);
    const key_slice = std.mem.span(key);

    for (ui.fonts, 0..) |f, i| {
        if (f.in_use and std.mem.eql(u8, f.key, key_slice))
            return .{ .bits = handles.make(@intCast(i), c.KE_HANDLE_GENERATION_FIRST) };
    }

    var slot: ?usize = null;
    for (ui.fonts, 0..) |f, i| {
        if (!f.in_use) { slot = i; break; }
    }
    const idx = slot orelse {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "ui text: no free font slots", @src().file, @intCast(@src().line), null);
        return c.KE_UI_FONT_NONE;
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

    ui.fonts[idx] = .{
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

fn shapeLabel(ui: *UiState, l_ptr: [*c]c.ke_label_component, bb_w: u32, bb_h: u32) void {
    const l: *c.ke_label_component = @ptrCast(l_ptr);
    l.glyph_count = 0;

    const font_idx = handles.index(l.font_handle.bits);
    if (l.font_handle.bits == c.KE_HANDLE_NONE or font_idx >= MAX_UI_FONTS or !ui.fonts[font_idx].in_use)
        return;
    const font = &ui.fonts[font_idx];

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

fn uiBindGroupFor(ui: *UiState, tex: c.ke_texture_handle) c.ke_gpu_bind_group {
    const tex_idx = handles.index(tex.bits);
    if (ui.bind_group_cache[tex_idx] != c.KE_GPU_INVALID_HANDLE)
        return ui.bind_group_cache[tex_idx];

    const view = ui.core.*.texture_view.?(ui.core, tex);
    const entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = view, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = ui.core.*.sampler.?(ui.core) },
    };
    const bg = ui.device.create_bind_group.?(ui.device, &c.ke_gpu_bind_group_params{
        .layout = ui.bgl_tex,
        .entry_count = 2,
        .entries = &entries,
    }, null);
    ui.bind_group_cache[tex_idx] = bg;
    return bg;
}

inline fn moduleOf(user: ?*anyopaque) *UiState {
    return @alignCast(@ptrCast(user.?));
}

fn emitQuad(ui: *UiState, vertex_count: *u32, batch_count: *u32, tex_in: c.ke_texture_handle,
            x0: f32, y0: f32, x1: f32, y1: f32, tu0: f32, tv0: f32, tu1: f32, tv1: f32, color: [4]f32) void {
    if (vertex_count.* + 6 > ui.vertices.len) return;
    const tex = if (tex_in.bits == c.KE_HANDLE_NONE) ui.core.*.white_texture.?(ui.core) else tex_in;
    if (handles.index(tex.bits) >= MAX_UI_TEXTURES) return;

    const need_new_batch = batch_count.* == 0 or ui.batches[batch_count.* - 1].texture.bits != tex.bits;
    if (need_new_batch) {
        if (batch_count.* >= ui.batches.len) return;
        ui.batches[batch_count.*] = .{ .texture = tex, .first_vertex = vertex_count.*, .vertex_count = 0 };
        batch_count.* += 1;
    }

    const verts = [6]UiVertex{
        .{ .position = .{ x0, y0 }, .uv = .{ tu0, tv0 }, .color = color },
        .{ .position = .{ x1, y0 }, .uv = .{ tu1, tv0 }, .color = color },
        .{ .position = .{ x1, y1 }, .uv = .{ tu1, tv1 }, .color = color },
        .{ .position = .{ x0, y0 }, .uv = .{ tu0, tv0 }, .color = color },
        .{ .position = .{ x1, y1 }, .uv = .{ tu1, tv1 }, .color = color },
        .{ .position = .{ x0, y1 }, .uv = .{ tu0, tv1 }, .color = color },
    };
    @memcpy(ui.vertices[vertex_count.* .. vertex_count.* + 6], &verts);
    vertex_count.* += 6;
    ui.batches[batch_count.* - 1].vertex_count += 6;
}

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

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const ui = moduleOf(user);
    const core = ui.core;

    var quad_segc: usize = 0;
    const quad_segs = ctx.?.view.?(ctx, 0, &quad_segc);
    var label_segc: usize = 0;
    const label_segs = ctx.?.view.?(ctx, 1, &label_segc);
    if (quad_segc == 0 and label_segc == 0) return true;

    const pc = core.*.begin_pass.?(core, &ui.io);
    if (pc == null) return true;

    var vertex_count: u32 = 0;
    var batch_count: u32 = 0;

    var s: usize = 0;
    quad_loop: while (s < quad_segc) : (s += 1) {
        const quads: [*c]const UiQuadComponent = @ptrCast(@alignCast(quad_segs[s].columns[0]));
        var i: usize = 0;
        while (i < quad_segs[s].count) : (i += 1) {
            const q = quads[i];
            if (q.dst_w <= 0 or q.dst_h <= 0) continue;
            if (vertex_count + 6 > ui.vertices.len) break :quad_loop;
            emitQuad(ui, &vertex_count, &batch_count, .{ .bits = q.texture_bits },
                q.dst_x, q.dst_y, q.dst_x + q.dst_w, q.dst_y + q.dst_h,
                q.u0, q.v0, q.u1, q.v1, q.color);
        }
    }

    s = 0;
    label_loop: while (s < label_segc) : (s += 1) {
        const labels: [*c]const c.ke_label_component = @ptrCast(@alignCast(label_segs[s].columns[0]));
        var i: usize = 0;
        while (i < label_segs[s].count) : (i += 1) {
            const l = labels[i];
            if (l.glyph_count == 0) continue;

            const font_idx = handles.index(l.font_handle.bits);
            const tex = ui.fonts[font_idx].atlas;
            const premul = [4]f32{ l.color[0] * l.color[3], l.color[1] * l.color[3], l.color[2] * l.color[3], l.color[3] };

            var gi: u32 = 0;
            while (gi < l.glyph_count) : (gi += 1) {
                if (vertex_count + 6 > ui.vertices.len) break :label_loop;
                const g = l.glyphs[gi];
                emitQuad(ui, &vertex_count, &batch_count, tex,
                    g.dst_x, g.dst_y, g.dst_x + g.dst_w, g.dst_y + g.dst_h,
                    g.u0, g.v0, g.u1, g.v1, premul);
            }
        }
    }

    if (vertex_count == 0) {
        core.*.end_pass.?(core, pc);
        return true;
    }

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    var proj = zm.orthographicOffCenterLh(0.0, @floatFromInt(bw), 0.0, @floatFromInt(bh), 0.0, 1.0);
    if (ui.ndc.y_flip != 0) proj[1][1] = -proj[1][1];
    var proj_arr: [16]f32 = undefined;
    zm.storeMat(proj_arr[0..], proj);
    core.*.upload.?(core, ui.frame_uniform, 0, &proj_arr, 64);

    const bytes = std.mem.sliceAsBytes(ui.vertices[0..vertex_count]);
    core.*.upload.?(core, ui.vbo, 0, bytes.ptr, bytes.len);

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &ui.pipeline_params));
    rp.*.set_bind_group.?(rp, 0, ui.frame_bind_group, null, 0);
    rp.*.set_vertex_buffer.?(rp, 0, ui.vbo, 0);

    var i: u32 = 0;
    while (i < batch_count) : (i += 1) {
        const batch = ui.batches[i];
        rp.*.set_bind_group.?(rp, 1, uiBindGroupFor(ui, batch.texture), null, 0);
        rp.*.draw.?(rp, batch.vertex_count, 1, batch.first_vertex, 0);
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return true;
}

fn setup(ui: *UiState, dev: *c.ke_gpu_device, core: *c.ke_render_service,
         ndc: c.ke_ndc_convention, bb_cid: c.ke_component_id,
         cmd_slot: u32, out_error: [*c][*c]c.ke_error) bool {
    ui.core = core;
    ui.device = dev;
    ui.ndc = ndc;

    const vs = core.*.load_shader.?(core, "ui", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    const fs = core.*.load_shader.?(core, "ui", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;

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
    pp.color_target_formats[0] = 0;
    pp.color_target_count = 1;

    ui.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &ui.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "ui pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    ui.frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = 64,
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

    for (&ui.bind_group_cache) |*e| e.* = c.KE_GPU_INVALID_HANDLE;
    for (&ui.fonts) |*f| f.* = .{};

    ui.writes = .{"backbuffer"};
    ui.io = std.mem.zeroes(c.ke_render_pass_io);
    ui.io.writes = @ptrCast(&ui.writes);
    ui.io.writes_count = 1;
    ui.io.cmd_slot = cmd_slot;
    ui.io.load = 1;
    ui.access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
    };
    return true;
}

fn destroyState(ui: *const UiState) void {
    const dev = ui.device;
    if (ui.frame_bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, ui.frame_bind_group);
    for (ui.bind_group_cache) |bg| {
        if (bg != c.KE_GPU_INVALID_HANDLE) dev.destroy_bind_group.?(dev, bg);
    }
    for (ui.fonts) |f| {
        if (f.in_use) {
            gpa.free(f.key);
            gpa.free(f.glyphs);
        }
    }
}

fn destroyHandle(self: ?*c.ke_render_ui) callconv(.c) void {
    const ui: *UiState = @ptrCast(@alignCast(self orelse return));
    destroyState(ui);
    gpa.destroy(ui);
}

export fn ke_render_ui_create(runtime: ?*c.ke_runtime, ecs: ?*c.ke_ecs, core: ?*c.ke_render_service,
                               device: ?*c.ke_gpu_device, ndc: c.ke_ndc_convention,
                               bb_cid: c.ke_component_id, cmd_slot: u32,
                               out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_ui_handle {
    const empty = c.ke_render_ui_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const e = ecs orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const ui = gpa.create(UiState) catch return empty;
    ui.* = .{};
    ui.api = .{ .handle = ui, .load_font = uiLoadFont };
    if (!setup(ui, dev, core_ref, ndc, bb_cid, cmd_slot, out_error)) {
        gpa.destroy(ui);
        return empty;
    }

    ui.quad_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_UI_QUAD, @sizeOf(UiQuadComponent), &c.ke_ui_quad_component_fields, c.ke_ui_quad_component_fields.len, null);
    ui.queries[0].terms[0] = .{ .cid = ui.quad_cid, .access = c.KE_ACCESS_READ };
    ui.queries[0].term_count = 1;

    ui.label_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_LABEL, @sizeOf(c.ke_label_component), &c.ke_label_component_fields, c.ke_label_component_fields.len, null);
    ui.queries[1].terms[0] = .{ .cid = ui.label_cid, .access = c.KE_ACCESS_READ };
    ui.queries[1].term_count = 1;

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.ui";
    params.phase = c.KE_PHASE_RENDER;
    params.queries = &ui.queries;
    params.query_count = ui.queries.len;
    params.access_list = &ui.access;
    params.access_count = ui.access.len;
    params.pinned_thread = 0;
    params.user_data = ui;
    params.execute = system;
    _ = rt.register_system.?(rt, &params, null);

    ui.label_shape_queries[0].terms[0] = .{ .cid = ui.label_cid, .access = c.KE_ACCESS_WRITE };
    ui.label_shape_queries[0].term_count = 1;

    var shape_params = std.mem.zeroes(c.ke_runtime_system_params);
    shape_params.name = "render.ui.labels";
    shape_params.phase = c.KE_PHASE_UPDATE;
    shape_params.queries = &ui.label_shape_queries;
    shape_params.query_count = ui.label_shape_queries.len;
    shape_params.pinned_thread = 0;
    shape_params.user_data = ui;
    shape_params.execute = labelShapeSystem;
    _ = rt.register_system.?(rt, &shape_params, null);

    return .{ .ref = @ptrCast(&ui.api), .destroy = destroyHandle };
}
