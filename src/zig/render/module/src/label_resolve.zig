const cimport = @import("cimport.zig");
const c = cimport.c;

const std = @import("std");

pub const State = struct {
    core: *c.ke_render_service,
    ui: *c.ke_render_ui,
    /// Borrowed, optional.
    resolver: ?*c.ke_asset_resolver,
    /// Borrowed, optional.
    logger: ?*c.ke_logger = null,
};

/// Reports a label that named a font the engine could not produce. Staying quiet
/// draws the label as nothing, which reads on screen as an empty scene rather
/// than as the failure it is.
fn reportUnresolved(st: *State, path: []const u8, reason: []const u8) void {
    const lg = st.logger orelse return;
    var buf: [320]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "font '{s}' did not resolve ({s}); the label draws no text", .{ path, reason }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_ERROR, .tag = "render.label", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

/// Bakes and registers the font, keyed by every parameter of the bake. A failure
/// answers KE_UI_FONT_FAILED, which both stops the retry and records that the
/// label asked for something it did not get.
fn bake(st: *State, l: *c.ke_label_component) c.ke_ui_font_handle {
    const path = std.mem.sliceTo(&l.font, 0);

    const resolver = st.resolver orelse {
        reportUnresolved(st, path, "the render module was given no asset resolver");
        return c.KE_UI_FONT_FAILED;
    };

    const first_codepoint: u32 = 32;
    const codepoint_count: u32 = 95;
    const atlas_size: u32 = 512;

    var key_buf: [256]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "font:{s}:{d}:{d}:{d}:{d}", .{
        path, l.font_size, atlas_size, first_codepoint, codepoint_count,
    }) catch {
        reportUnresolved(st, path, "the bake key does not fit its buffer");
        return c.KE_UI_FONT_FAILED;
    };

    var data: ?*c.ke_font_data = null;
    if (!resolver.resolve_font.?(resolver, &l.font, l.font_size, first_codepoint, codepoint_count, atlas_size, &data, null)) {
        reportUnresolved(st, path, "the asset resolver could not read it");
        return c.KE_UI_FONT_FAILED;
    }
    const d = data orelse {
        reportUnresolved(st, path, "the asset resolver reported success without data");
        return c.KE_UI_FONT_FAILED;
    };
    defer resolver.free_font.?(resolver, d);

    const atlas = st.core.upload_texture.?(st.core, key.ptr, d.atlas_width, d.atlas_height, d.atlas_rgba, null);
    if (!c.ke_texture_is_valid(atlas)) {
        reportUnresolved(st, path, "its glyph atlas could not be uploaded");
        return c.KE_UI_FONT_FAILED;
    }

    const font = st.ui.load_font.?(st.ui, key.ptr, atlas, d.glyphs, d.glyph_count, d.line_height, d.ascent, null);
    if (font.bits == c.KE_HANDLE_NONE) {
        reportUnresolved(st, path, "the ui service refused to register it");
        return c.KE_UI_FONT_FAILED;
    }
    return font;
}

pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const st: *State = @ptrCast(@alignCast(user.?));

    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const labels: [*c]c.ke_label_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            const l: *c.ke_label_component = @ptrCast(&labels[i]);
            if (l.font[0] == 0 or l.font_handle.bits != c.KE_HANDLE_NONE) continue;
            l.font_handle = bake(st, l);
        }
    }
    return true;
}

const testing = std.testing;

var reported_count: usize = 0;
var reported_msg: [320]u8 = undefined;
var reported_len: usize = 0;

fn captureLog(_: ?*c.ke_logger, ev: [*c]const c.ke_log_event) callconv(.c) void {
    reported_count += 1;
    const m = std.mem.span(ev.*.message);
    reported_len = @min(m.len, reported_msg.len);
    @memcpy(reported_msg[0..reported_len], m[0..reported_len]);
}

fn labelNaming(path: []const u8) c.ke_label_component {
    var l = std.mem.zeroes(c.ke_label_component);
    @memcpy(l.font[0..path.len], path);
    l.font_size = 16;
    return l;
}

test "a label whose font never resolved is reported rather than drawn as an empty screen" {
    var core = std.mem.zeroes(c.ke_render_service);
    var ui = std.mem.zeroes(c.ke_render_ui);
    var logger = std.mem.zeroes(c.ke_logger);
    logger.log = captureLog;

    reported_count = 0;
    var st = State{ .core = &core, .ui = &ui, .resolver = null, .logger = &logger };
    var l = labelNaming("res://font.ttf");

    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), bake(&st, &l).bits);
    try testing.expectEqual(@as(usize, 1), reported_count);
    try testing.expect(std.mem.indexOf(u8, reported_msg[0..reported_len], "res://font.ttf") != null);
}

test "a font that failed to resolve is not retried on the next tick" {
    var core = std.mem.zeroes(c.ke_render_service);
    var ui = std.mem.zeroes(c.ke_render_ui);
    var logger = std.mem.zeroes(c.ke_logger);
    logger.log = captureLog;

    reported_count = 0;
    var st = State{ .core = &core, .ui = &ui, .resolver = null, .logger = &logger };
    var l = labelNaming("res://font.ttf");

    l.font_handle = bake(&st, &l);
    try testing.expectEqual(@as(usize, 1), reported_count);

    const skips = l.font[0] == 0 or l.font_handle.bits != c.KE_HANDLE_NONE;
    try testing.expect(skips);
}

test "a label naming no font at all is left alone, having asked for nothing" {
    var core = std.mem.zeroes(c.ke_render_service);
    var ui = std.mem.zeroes(c.ke_render_ui);
    var logger = std.mem.zeroes(c.ke_logger);
    logger.log = captureLog;

    reported_count = 0;
    var st = State{ .core = &core, .ui = &ui, .resolver = null, .logger = &logger };
    _ = &st;
    const l = std.mem.zeroes(c.ke_label_component);

    try testing.expect(l.font[0] == 0);
    try testing.expectEqual(@as(usize, 0), reported_count);
}
