// "render.label.resolve" — bakes the font a label names and registers it with
// the overlay pass.
//
// A label used to receive a font handle, which meant the only way to have one
// was to bake the font in the host's own language and hand the value over: the
// C# Font class did it, and no scene and no other language could. Naming the
// file in the component moves the whole path — decode, atlas upload, glyph table
// — behind a system every host gets for free.
//
// Lives here rather than in the ui plugin because this is where the pieces meet:
// the asset resolver the host supplied, the render service that owns textures,
// and the overlay pass's own load_font. The ui plugin knows none of the first.

const cimport = @import("cimport.zig");
const c = cimport.c;

const std = @import("std");

pub const State = struct {
    core: *c.ke_render_service,
    ui: *c.ke_render_ui,
    /// Borrowed, optional: null where the host wired no font loader, and a label
    /// naming a file then draws nothing rather than failing a frame.
    resolver: ?*c.ke_asset_resolver,
};

/// The bake is keyed by every parameter that changes its pixels, so the same
/// file at another size is a different atlas rather than a silent reuse.
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
    const st: *State = @alignCast(@ptrCast(user.?));

    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const labels: [*c]c.ke_label_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            const l: *c.ke_label_component = @ptrCast(&labels[i]);
            // A label handed a handle directly keeps it: the bake is for the ones
            // that named a file, and load_font dedups the rest by key anyway.
            if (l.font[0] == 0 or l.font_handle.bits != c.KE_HANDLE_NONE) continue;
            l.font_handle = bake(st, l);
        }
    }
}
