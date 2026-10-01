const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const heap = @import("heap");
const gpa = heap.gpa;

const stb = @cImport({
    @cInclude("stb_truetype.h");
});

const libc = @cImport({
    @cInclude("stdio.h");
});

const c = @cImport({
    @cInclude("kernel_engine/text/stb_truetype/stb_font.h");
    @cInclude("kernel_engine/logger/logger.h");
});

const E = @import("kerror").Errors(c);

const State = struct {
    logger: ?*c.ke_logger,
};

fn destroy(self: ?*c.ke_font_loader) callconv(.c) void {
    const loader = self orelse return;
    const state: *State = @ptrCast(@alignCast(loader.handle));
    gpa.destroy(state);
    gpa.destroy(loader);
}

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

fn loadFont(
    self: ?*c.ke_font_loader,
    path: [*c]const u8,
    pixel_size: f32,
    first_codepoint: u32,
    codepoint_count: u32,
    atlas_size: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) [*c]c.ke_font_data {
    if (self == null or path == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null;
    }
    if (pixel_size <= 0.0 or atlas_size == 0 or codepoint_count == 0) {
        E.fail(out_error, .invalid_argument, "invalid font parameters", @src());
        return null;
    }

    const ttf = readFile(path) orelse {
        E.fail(out_error, .io, "failed to open or read font file", @src());
        return null;
    };
    defer gpa.free(ttf);

    const w = atlas_size;
    const h = atlas_size;
    const alpha = gpa.alloc(u8, @as(usize, w) * @as(usize, h)) catch {
        E.fail(out_error, .out_of_memory, "atlas alpha buffer allocation failed", @src());
        return null;
    };
    defer gpa.free(alpha);
    @memset(alpha, 0);

    var pc: stb.stbtt_pack_context = undefined;
    if (stb.stbtt_PackBegin(&pc, alpha.ptr, @intCast(w), @intCast(h), 0, 1, null) == 0) {
        E.fail(out_error, .general, "stbtt_PackBegin failed", @src());
        return null;
    }
    stb.stbtt_PackSetOversampling(&pc, 1, 1);

    const chars = gpa.alloc(stb.stbtt_packedchar, codepoint_count) catch {
        stb.stbtt_PackEnd(&pc);
        E.fail(out_error, .out_of_memory, "packed-char buffer allocation failed", @src());
        return null;
    };
    defer gpa.free(chars);

    if (stb.stbtt_PackFontRange(&pc, ttf.ptr, 0, pixel_size, @intCast(first_codepoint), @intCast(codepoint_count), chars.ptr) == 0) {
        stb.stbtt_PackEnd(&pc);
        E.fail(out_error, .general, "stbtt_PackFontRange failed", @src());
        return null;
    }
    stb.stbtt_PackEnd(&pc);

    const atlas_rgba = gpa.alloc(u8, @as(usize, w) * @as(usize, h) * 4) catch {
        E.fail(out_error, .out_of_memory, "atlas allocation failed", @src());
        return null;
    };
    for (0..@as(usize, w) * @as(usize, h)) |i| {
        atlas_rgba[i * 4 + 0] = 0xFF;
        atlas_rgba[i * 4 + 1] = 0xFF;
        atlas_rgba[i * 4 + 2] = 0xFF;
        atlas_rgba[i * 4 + 3] = alpha[i];
    }

    var info: stb.stbtt_fontinfo = undefined;
    if (stb.stbtt_InitFont(&info, ttf.ptr, stb.stbtt_GetFontOffsetForIndex(ttf.ptr, 0)) == 0) {
        gpa.free(atlas_rgba);
        E.fail(out_error, .general, "stbtt_InitFont failed", @src());
        return null;
    }
    var ascent_i: c_int = 0;
    var descent_i: c_int = 0;
    var line_gap_i: c_int = 0;
    stb.stbtt_GetFontVMetrics(&info, &ascent_i, &descent_i, &line_gap_i);
    const scale = stb.stbtt_ScaleForPixelHeight(&info, pixel_size);
    const ascent = @as(f32, @floatFromInt(ascent_i)) * scale;
    const line_h = @as(f32, @floatFromInt(ascent_i - descent_i + line_gap_i)) * scale;

    const glyphs = gpa.alloc(c.ke_glyph_metrics, codepoint_count) catch {
        gpa.free(atlas_rgba);
        E.fail(out_error, .out_of_memory, "glyphs allocation failed", @src());
        return null;
    };

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

    const fd = gpa.create(c.ke_font_data) catch {
        gpa.free(atlas_rgba);
        gpa.free(glyphs);
        E.fail(out_error, .out_of_memory, "font_data allocation failed", @src());
        return null;
    };
    fd.atlas_rgba = atlas_rgba.ptr;
    fd.atlas_width = w;
    fd.atlas_height = h;
    fd.glyphs = glyphs.ptr;
    fd.glyph_count = codepoint_count;
    fd.line_height = line_h;
    fd.ascent = ascent;

    return fd;
}

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

export fn ke_font_loader_stb_create(
    params: [*c]const c.ke_font_loader_stb_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_font_loader_handle {
    const empty = c.ke_font_loader_handle{ .ref = null, .destroy = null };
    if (params == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return empty;
    }

    const state = gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "loader allocation failed", @src());
        return empty;
    };
    state.* = .{ .logger = params.*.logger };

    const loader = gpa.create(c.ke_font_loader) catch {
        gpa.destroy(state);
        E.fail(out_error, .out_of_memory, "loader allocation failed", @src());
        return empty;
    };
    loader.handle = state;
    loader.load_font = &loadFont;
    loader.free_font = &freeFont;

    return .{ .ref = loader, .destroy = &destroy };
}

const testing = std.testing;

const font_candidates = [_][*c]const u8{
    "C:/Windows/Fonts/arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
};

fn createLoader() c.ke_font_loader_handle {
    var params = std.mem.zeroes(c.ke_font_loader_stb_params);
    params.logger = null;
    return ke_font_loader_stb_create(&params, null);
}

test "creating the loader with null params returns a null handle" {
    const h = ke_font_loader_stb_create(null, null);
    try testing.expect(h.ref == null);
}

test "loading a font from a null path fails" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    const data = h.ref.*.load_font.?(h.ref, null, 16.0, 32, 96, 512, null);
    try testing.expect(data == null);
}

test "loading a font with a zero pixel size fails" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    const data = h.ref.*.load_font.?(h.ref, "test.ttf", 0.0, 32, 96, 512, null);
    try testing.expect(data == null);
}

test "loading a font with a negative pixel size fails" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    const data = h.ref.*.load_font.?(h.ref, "test.ttf", -1.0, 32, 96, 512, null);
    try testing.expect(data == null);
}

test "loading a font with a zero codepoint count fails" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    const data = h.ref.*.load_font.?(h.ref, "test.ttf", 16.0, 32, 0, 512, null);
    try testing.expect(data == null);
}

test "loading a font with a zero atlas size fails" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    const data = h.ref.*.load_font.?(h.ref, "test.ttf", 16.0, 32, 96, 0, null);
    try testing.expect(data == null);
}

test "loading a real system font produces an atlas with every requested glyph" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    for (font_candidates) |path| {
        const data = h.ref.*.load_font.?(h.ref, path, 16.0, 32, 96, 512, null);
        if (data != null) {
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
