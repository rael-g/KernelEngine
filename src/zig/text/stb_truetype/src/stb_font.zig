const std = @import("std");

// This .so is dlopen'd by a foreign, non-Zig host alongside many sibling
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack exceeds glibc's small static-TLS surplus once enough plugins
// accumulate, aborting with "cannot allocate memory in static TLS block".
pub const std_options: std.Options = .{ .signal_stack_size = null };

// Windows: mingw's crtdll must own the DLL entry point so the statically
// linked C/C++ dependency's initializers actually run. See kerror.zig.
pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const gpa = std.heap.c_allocator;

// Declarations only — the implementation is compiled as C from
// stb_font_impl.c (see build.zig); translate-c cannot reliably lower stb's
// bit-packed internals, so @cImport never sees STB_TRUETYPE_IMPLEMENTATION.
const stb = @cImport({
    @cInclude("stb_truetype.h");
});

// Zig 0.16 moved file IO behind std.Io (needs an Io instance to construct;
// std.posix.read explicitly refuses Windows in this version). libc is
// already linked — same choice shader_loader.zig made for the same reason.
const libc = @cImport({
    @cInclude("stdio.h");
});

const c = @cImport({
    @cInclude("kernel_engine/text/stb_truetype/stb_font.h");
    @cInclude("kernel_engine/logger/logger.h");
});

// Zig-native error translation at the C-ABI seam (no ke_common link).
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

    // 1. Slurp the TTF.
    const ttf = readFile(path) orelse {
        E.fail(out_error, .io, "failed to open or read font file", @src());
        return null;
    };
    defer gpa.free(ttf);

    // 2. Pack the requested codepoint range into a grayscale alpha atlas.
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

    // 3. Expand alpha -> RGBA8 (white RGB + glyph-coverage alpha).
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

    // 4. Glyph metrics + line-height from the unscaled font's v-metrics scaled to pixel_size.
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
        glyphs[i].bearing_y = -pcc.yoff; // stb yoff is +down from top of glyph; we want +up from baseline
        glyphs[i].advance_x = pcc.xadvance;
    }

    // 5. Assemble ke_font_data.
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
