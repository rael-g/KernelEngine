//! Implements the font-loader contract on stb_truetype: it bakes a codepoint range of a font file
//! into an RGBA atlas with a metrics record per glyph.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_text_stb_truetype").logFn };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const heap = @import("heap");
const gpa = heap.gpa;

const stb = @import("c");

const libc = @import("c");

const c = @import("c");

const R = @import("result").Result(c, .{});
const log = std.log.scoped(.text_stb_truetype);

/// The loader: the vtable the handle refers to, whose `handle` points back at the state. It holds
/// nothing else, since a bake needs only its arguments.
const State = struct {
    api: c.ke_font_loader,
};

fn stateOf(self: *c.ke_font_loader) *State {
    return @fieldParentPtr("api", self);
}

/// Frees the loader that `ke_font_loader_stb_create` allocated. A null loader is ignored. Fonts
/// already loaded are separate allocations and stay valid until freed.
fn destroy(self: ?*c.ke_font_loader) callconv(.c) void {
    const loader = self orelse return;
    gpa.destroy(stateOf(loader));
}

/// Returns the whole file, or null when it cannot be opened, is empty, cannot be allocated, or
/// reads short. Null covers all of these causes, so the caller reports them as one error.
fn readFile(path: [*c]const u8) ?[]u8 {
    const fp = libc.fopen(path, "rb") orelse return null;
    defer _ = libc.fclose(fp);
    _ = libc.fseek(fp, 0, libc.SEEK_END);
    const size = libc.ftell(fp);
    _ = libc.fseek(fp, 0, libc.SEEK_SET);
    if (size <= 0) return null;

    const buf = gpa.alloc(u8, @intCast(size)) catch return null;
    const read = libc.fread(buf.ptr, 1, buf.len, fp);
    if (read != buf.len) {
        gpa.free(buf);
        return null;
    }
    return buf;
}

/// Runs in the `load_font` slot, on the calling thread. On success the caller owns `out_font.*`
/// and releases it through `free_font`; on failure it is null and nothing `bake` allocated
/// survives.
fn loadFont(
    self: ?*c.ke_font_loader,
    path: [*c]const u8,
    pixel_size: f32,
    first_codepoint: u32,
    codepoint_count: u32,
    atlas_size: u32,
    out_font: ?*[*c]c.ke_font_data,
) callconv(.c) c.ke_result {
    const out = out_font orelse return R.code(error.InvalidArgument);
    out.* = null;
    if (self == null or path == null) return R.code(error.InvalidArgument);
    out.* = bake(path, pixel_size, first_codepoint, codepoint_count, atlas_size) catch |err| {
        log.warn("baking {s} failed: {t}", .{ path, err });
        return R.code(err);
    };
    return R.ok;
}

/// Reads the whole file, packs the range into an alpha-only buffer with the stb packer, and only
/// then widens that buffer into white pixels carrying the alpha; glyph rectangles come back from
/// the packer as pixels and are stored as texture coordinates. The result is allocated last, so
/// the caller gets a complete `ke_font_data` or an error, never a partial one, and the pack context
/// is ended whenever it was begun. Fails with invalid argument for a non-positive pixel size or a
/// zero atlas size or codepoint count, io when the file cannot be read, out of memory, and general
/// when the packer cannot begin or pack the range or the font cannot be initialised.
fn bake(path: [*c]const u8, pixel_size: f32, first_codepoint: u32, codepoint_count: u32, atlas_size: u32) R.Error!*c.ke_font_data {
    if (pixel_size <= 0.0 or atlas_size == 0 or codepoint_count == 0) return error.InvalidArgument;

    const ttf = readFile(path) orelse return error.Io;
    defer gpa.free(ttf);

    const w = atlas_size;
    const h = atlas_size;
    const alpha = gpa.alloc(u8, @as(usize, w) * @as(usize, h)) catch return error.OutOfMemory;
    defer gpa.free(alpha);
    @memset(alpha, 0);

    const chars = gpa.alloc(stb.stbtt_packedchar, codepoint_count) catch return error.OutOfMemory;
    defer gpa.free(chars);

    var pc: stb.stbtt_pack_context = undefined;
    if (stb.stbtt_PackBegin(&pc, alpha.ptr, @intCast(w), @intCast(h), 0, 1, null) == 0) return error.General;
    stb.stbtt_PackSetOversampling(&pc, 1, 1);
    const packed_range = stb.stbtt_PackFontRange(&pc, ttf.ptr, 0, pixel_size, @intCast(first_codepoint), @intCast(codepoint_count), chars.ptr);
    stb.stbtt_PackEnd(&pc);
    if (packed_range == 0) return error.General;

    const atlas_rgba = gpa.alloc(u8, @as(usize, w) * @as(usize, h) * 4) catch return error.OutOfMemory;
    errdefer gpa.free(atlas_rgba);
    for (0..@as(usize, w) * @as(usize, h)) |i| {
        atlas_rgba[i * 4 + 0] = 0xFF;
        atlas_rgba[i * 4 + 1] = 0xFF;
        atlas_rgba[i * 4 + 2] = 0xFF;
        atlas_rgba[i * 4 + 3] = alpha[i];
    }

    var info: stb.stbtt_fontinfo = undefined;
    if (stb.stbtt_InitFont(&info, ttf.ptr, stb.stbtt_GetFontOffsetForIndex(ttf.ptr, 0)) == 0) return error.General;
    var ascent_i: c_int = 0;
    var descent_i: c_int = 0;
    var line_gap_i: c_int = 0;
    stb.stbtt_GetFontVMetrics(&info, &ascent_i, &descent_i, &line_gap_i);
    const scale = stb.stbtt_ScaleForPixelHeight(&info, pixel_size);
    const ascent = @as(f32, @floatFromInt(ascent_i)) * scale;
    const line_h = @as(f32, @floatFromInt(ascent_i - descent_i + line_gap_i)) * scale;

    const glyphs = gpa.alloc(c.ke_glyph_metrics, codepoint_count) catch return error.OutOfMemory;
    errdefer gpa.free(glyphs);

    for (0..codepoint_count) |i| {
        const pcc = chars[i];
        glyphs[i].codepoint = first_codepoint + @as(u32, @intCast(i));
        glyphs[i].u0 = @as(f32, @floatFromInt(pcc.x0)) / @as(f32, @floatFromInt(w));
        glyphs[i].v0 = @as(f32, @floatFromInt(pcc.y0)) / @as(f32, @floatFromInt(h));
        glyphs[i].u1 = @as(f32, @floatFromInt(pcc.x1)) / @as(f32, @floatFromInt(w));
        glyphs[i].v1 = @as(f32, @floatFromInt(pcc.y1)) / @as(f32, @floatFromInt(h));
        glyphs[i].width = @floatFromInt(pcc.x1 - pcc.x0);
        glyphs[i].height = @floatFromInt(pcc.y1 - pcc.y0);
        glyphs[i].bearing_x = pcc.xoff;
        glyphs[i].bearing_y = -pcc.yoff;
        glyphs[i].advance_x = pcc.xadvance;
    }

    const fd = gpa.create(c.ke_font_data) catch return error.OutOfMemory;
    fd.* = .{
        .atlas_rgba = atlas_rgba.ptr,
        .atlas_width = w,
        .atlas_height = h,
        .glyphs = glyphs.ptr,
        .glyph_count = codepoint_count,
        .line_height = line_h,
        .ascent = ascent,
    };
    return fd;
}

/// Runs in the `free_font` slot. It sizes the atlas and glyph arrays from `atlas_width`,
/// `atlas_height` and `glyph_count`, so those fields must still hold what `loadFont` wrote.
fn freeFont(self: ?*c.ke_font_loader, data: [*c]c.ke_font_data) callconv(.c) void {
    _ = self;
    if (data == null) return;
    const d: *c.ke_font_data = @ptrCast(data);
    if (d.atlas_rgba != null) {
        const pixel_bytes: usize = @as(usize, d.atlas_width) * @as(usize, d.atlas_height) * 4;
        gpa.free(@as([*]u8, @ptrCast(d.atlas_rgba))[0..pixel_bytes]);
    }
    if (d.glyphs != null) {
        gpa.free(@as([*]c.ke_glyph_metrics, @ptrCast(d.glyphs))[0..d.glyph_count]);
    }
    gpa.destroy(d);
}

/// Allocates the loader and fills the `load_font` and `free_font` slots; the handle's `destroy`
/// releases it. Fails with out of memory when it cannot be allocated, leaving the handle zeroed.
export fn ke_font_loader_stb_create(out_loader: ?*c.ke_font_loader_handle) callconv(.c) c.ke_result {
    const out = out_loader orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const state = gpa.create(State) catch {
        log.warn("creating the font loader failed: out of memory", .{});
        return R.code(error.OutOfMemory);
    };
    state.* = .{ .api = .{ .handle = state, .load_font = &loadFont, .free_font = &freeFont } };
    out.* = .{ .ref = &state.api, .destroy = &destroy };
    return R.ok;
}

const testing = std.testing;

const font_candidates = [_][*c]const u8{
    "C:/Windows/Fonts/arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
};

fn createLoader() !c.ke_font_loader_handle {
    var h: c.ke_font_loader_handle = undefined;
    try R.check(ke_font_loader_stb_create(&h));
    return h;
}

test "loading a font from a null path fails" {
    const h = try createLoader();
    defer h.destroy.?(h.ref);

    var data: [*c]c.ke_font_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.*.load_font.?(h.ref, null, 16.0, 32, 96, 512, &data)));
    try testing.expect(data == null);
}

test "loading a font with a zero pixel size fails" {
    const h = try createLoader();
    defer h.destroy.?(h.ref);

    var data: [*c]c.ke_font_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.*.load_font.?(h.ref, "test.ttf", 0.0, 32, 96, 512, &data)));
    try testing.expect(data == null);
}

test "loading a font with a negative pixel size fails" {
    const h = try createLoader();
    defer h.destroy.?(h.ref);

    var data: [*c]c.ke_font_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.*.load_font.?(h.ref, "test.ttf", -1.0, 32, 96, 512, &data)));
    try testing.expect(data == null);
}

test "loading a font with a zero codepoint count fails" {
    const h = try createLoader();
    defer h.destroy.?(h.ref);

    var data: [*c]c.ke_font_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.*.load_font.?(h.ref, "test.ttf", 16.0, 32, 0, 512, &data)));
    try testing.expect(data == null);
}

test "loading a font with a zero atlas size fails" {
    const h = try createLoader();
    defer h.destroy.?(h.ref);

    var data: [*c]c.ke_font_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.*.load_font.?(h.ref, "test.ttf", 16.0, 32, 96, 0, &data)));
    try testing.expect(data == null);
}

test "loading a real system font produces an atlas with every requested glyph" {
    const h = try createLoader();
    defer h.destroy.?(h.ref);

    for (font_candidates) |path| {
        var data: [*c]c.ke_font_data = null;
        if (h.ref.*.load_font.?(h.ref, path, 16.0, 32, 96, 512, &data) == R.ok) {
            defer h.ref.*.free_font.?(h.ref, data);
            try testing.expectEqual(@as(u32, 96), data.*.glyph_count);
            try testing.expect(data.*.atlas_rgba != null);
            return;
        }
    }
    return error.SkipZigTest;
}

test "destroying a null loader is a no-op" {
    destroy(null);
}

test "creating and destroying the font loader leaves no block allocated" {
    const h = try createLoader();
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}
