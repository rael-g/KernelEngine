const cimport = @import("cimport.zig");
const c = cimport.c;

const std = @import("std");

pub const State = struct {
    core: *c.ke_render_service,
    ui: *c.ke_render_ui,
    /// Borrowed, optional.
    resolver: ?*c.ke_asset_resolver,
};

/// Bakes and registers the font, keyed by every parameter of the bake.
fn bake(st: *State, l: *c.ke_label_component) c.ke_ui_font_handle {
    const resolver = st.resolver orelse return c.KE_UI_FONT_NONE;

    const first_codepoint: u32 = 32;
    const codepoint_count: u32 = 95;
    const atlas_size: u32 = 512;

    var key_buf: [256]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "font:{s}:{d}:{d}:{d}:{d}", .{
        std.mem.sliceTo(&l.font, 0), l.font_size, atlas_size, first_codepoint, codepoint_count,
    }) catch return c.KE_UI_FONT_NONE;

    var data: ?*c.ke_font_data = null;
    if (!resolver.resolve_font.?(resolver, &l.font, l.font_size, first_codepoint, codepoint_count, atlas_size, &data, null))
        return c.KE_UI_FONT_NONE;
    const d = data orelse return c.KE_UI_FONT_NONE;
    defer resolver.free_font.?(resolver, d);

    const atlas = st.core.upload_texture.?(st.core, key.ptr, d.atlas_width, d.atlas_height, d.atlas_rgba, null);
    if (!c.ke_texture_is_valid(atlas)) return c.KE_UI_FONT_NONE;

    return st.ui.load_font.?(st.ui, key.ptr, atlas, d.glyphs, d.glyph_count, d.line_height, d.ascent, null);
}

pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
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
}

const testing = std.testing;

test "a label draws unfonted where no resolver was wired, rather than failing the frame" {
    var core = std.mem.zeroes(c.ke_render_service);
    var ui = std.mem.zeroes(c.ke_render_ui);
    var st = State{ .core = &core, .ui = &ui, .resolver = null };
    var l = std.mem.zeroes(c.ke_label_component);
    @memcpy(l.font[0.."res://font.ttf".len], "res://font.ttf");
    l.font_size = 16;
    try testing.expectEqual(@as(u32, c.KE_HANDLE_NONE), bake(&st, &l).bits);
}
