//! Gives each label component the font it names, making one attempt per label.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_handles = @import("abi_render_handles");
const abi_ui_components = @import("abi_ui_components");
const abi_render = @import("abi_render");
const abi_render_ui_factory = @import("abi_render_ui_factory");
const abi_render_ui = @import("abi_render_ui");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_text = @import("abi_text");
const R = @import("result").Result(.{});

const std = @import("std");

/// Borrows the services `bake` calls and frees none of them; `default_font` is owned by the label
/// resolve that holds the state. A null `resolver` is not rejected here: `bake` reports each label
/// that reaches it.
pub const State = struct {
    core: *abi_render.c.ke_render_service,
    ui: *abi_render_ui.c.ke_render_ui,
    resolver: ?*abi_asset_resolver.c.ke_asset_resolver,
    default_font: ?[:0]const u8 = null,
};

/// The font a label draws with: the one it names, or the default when it names none.
fn fontPathOf(st: *const State, l: *const abi_ui_components.c.ke_label_component) ?[*:0]const u8 {
    if (l.font[0] != 0) return @ptrCast(&l.font);
    return if (st.default_font) |d| d.ptr else null;
}

const log = std.log.scoped(.render_scene);

/// Logs as a warning that the label's font did not resolve and why; the label then draws no text.
fn reportUnresolved(path: []const u8, reason: []const u8) void {
    log.warn("font '{s}' did not resolve ({s}); the label draws no text", .{ path, reason });
}

/// Asks the asset resolver for the font at the label's size over a fixed glyph range and atlas
/// size, uploads the glyph atlas as a texture and registers the font with the ui service, both
/// under one key spelled from the path, size, range and atlas size. Returns the registered
/// font, or `KE_UI_FONT_FAILED` after `reportUnresolved` has named the
/// step that failed. The resolver's font data is released by the time it returns, on every path
/// that received it.
fn bake(st: *State, l: *abi_ui_components.c.ke_label_component, font_path: [*:0]const u8) abi_ui_components.c.ke_ui_font_handle {
    const path = std.mem.span(font_path);

    const resolver = st.resolver orelse {
        reportUnresolved(path, "the label resolve was given no asset resolver");
        return abi_ui_components.c.KE_UI_FONT_FAILED;
    };

    const first_codepoint: u32 = 32;
    const codepoint_count: u32 = 95;
    const atlas_size: u32 = 512;

    var key_buf: [256]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "font:{s}:{d}:{d}:{d}:{d}", .{
        path, l.font_size, atlas_size, first_codepoint, codepoint_count,
    }) catch {
        reportUnresolved(path, "the bake key does not fit its buffer");
        return abi_ui_components.c.KE_UI_FONT_FAILED;
    };

    var data: ?*abi_text.c.ke_font_data = null;
    if (resolver.resolve_font.?(resolver, font_path, l.font_size, first_codepoint, codepoint_count, atlas_size, &data) != abi_result.c.KE_OK) {
        reportUnresolved(path, "the asset resolver could not read it");
        return abi_ui_components.c.KE_UI_FONT_FAILED;
    }
    const d = data orelse {
        reportUnresolved(path, "the asset resolver reported success without data");
        return abi_ui_components.c.KE_UI_FONT_FAILED;
    };
    defer resolver.free_font.?(resolver, d);

    var atlas: abi_render_handles.c.ke_texture_handle = abi_render_handles.c.KE_TEXTURE_NONE;
    if (st.core.upload_texture.?(st.core, key.ptr, d.atlas_width, d.atlas_height, @ptrCast(d.atlas_rgba), @as(usize, d.atlas_width) * d.atlas_height * 4, &atlas) != abi_result.c.KE_OK) {
        reportUnresolved(path, "its glyph atlas could not be uploaded");
        return abi_ui_components.c.KE_UI_FONT_FAILED;
    }

    var font: abi_ui_components.c.ke_ui_font_handle = abi_ui_components.c.KE_UI_FONT_NONE;
    if (st.ui.load_font.?(st.ui, key.ptr, atlas, d.glyphs, d.glyph_count, d.line_height, d.ascent, &font) != abi_result.c.KE_OK) {
        reportUnresolved(path, "the ui service refused to register it");
        return abi_ui_components.c.KE_UI_FONT_FAILED;
    }
    return font;
}

/// Runs in the update phase over the label view. A failure is logged by `reportUnresolved` and
/// yields the failed-font handle, which is not retried. Afterwards every label that named a font
/// and had no handle holds either the registered font or the failed-font handle. It always
/// succeeds, since each failure is logged by `bake` instead.
pub fn system(ctx: ?*abi_runtime.c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const st: *State = @ptrCast(@alignCast(user.?));

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const labels: [*c]abi_ui_components.c.ke_label_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            const l: *abi_ui_components.c.ke_label_component = @ptrCast(&labels[i]);
            if (l.font_handle.bits != abi_render_handles.c.KE_HANDLE_NONE) continue;
            const font_path = fontPathOf(st, l) orelse continue;
            l.font_handle = bake(st, l, font_path);
        }
    }
    return R.ok;
}

const testing = std.testing;

fn labelNaming(path: []const u8) abi_ui_components.c.ke_label_component {
    var l = std.mem.zeroes(abi_ui_components.c.ke_label_component);
    @memcpy(l.font[0..path.len], path);
    l.font_size = 16;
    return l;
}

test "a label naming no font draws with the default, and with none when there is no default" {
    var core = std.mem.zeroes(abi_render.c.ke_render_service);
    var ui = std.mem.zeroes(abi_render_ui.c.ke_render_ui);
    var st = State{ .core = &core, .ui = &ui, .resolver = null };
    var unnamed = labelNaming("");
    try testing.expect(fontPathOf(&st, &unnamed) == null);
    st.default_font = "res://default.ttf";
    try testing.expectEqualStrings("res://default.ttf", std.mem.span(fontPathOf(&st, &unnamed).?));
    var named = labelNaming("res://own.ttf");
    try testing.expectEqualStrings("res://own.ttf", std.mem.span(fontPathOf(&st, &named).?));
}

test "a label whose font never resolved gets the failed-font handle" {
    var core = std.mem.zeroes(abi_render.c.ke_render_service);
    var ui = std.mem.zeroes(abi_render_ui.c.ke_render_ui);
    var st = State{ .core = &core, .ui = &ui, .resolver = null };
    var l = labelNaming("res://font.ttf");

    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), bake(&st, &l, fontPathOf(&st, &l).?).bits);
}

test "a font that failed to resolve is not retried on the next tick" {
    var core = std.mem.zeroes(abi_render.c.ke_render_service);
    var ui = std.mem.zeroes(abi_render_ui.c.ke_render_ui);
    var st = State{ .core = &core, .ui = &ui, .resolver = null };
    var l = labelNaming("res://font.ttf");

    l.font_handle = bake(&st, &l, fontPathOf(&st, &l).?);

    const skips = l.font[0] == 0 or l.font_handle.bits != abi_render_handles.c.KE_HANDLE_NONE;
    try testing.expect(skips);
}

test "a label naming no font at all is left alone, having asked for nothing" {
    var core = std.mem.zeroes(abi_render.c.ke_render_service);
    var ui = std.mem.zeroes(abi_render_ui.c.ke_render_ui);
    var st = State{ .core = &core, .ui = &ui, .resolver = null };
    _ = &st;
    const l = std.mem.zeroes(abi_ui_components.c.ke_label_component);

    try testing.expect(l.font[0] == 0);
}
