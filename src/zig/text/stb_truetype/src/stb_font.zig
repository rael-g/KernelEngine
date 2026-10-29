//! Implements the font-loader contract on stb_truetype: it bakes a codepoint range of a font file
//! into an RGBA atlas with a metrics record per glyph.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_text_stb_truetype").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const heap = @import("heap");
const gpa = heap.gpa;

const stb = @import("c");
const abi_io = @import("abi_io");
const abi_result = @import("abi_result");
const abi_text = @import("abi_text");
const abi_stb = @import("abi_text_stb_truetype_factory");

const libc = @import("c");

const R = @import("result").Result(.{});
const log = std.log.scoped(.text_stb_truetype);

/// The loader: the vtable the handle refers to, whose `handle` points back at the state, and the
/// borrowed io every bake reads its font file through.
const State = struct {
    api: abi_text.ke_font_loader,
    io: *abi_io.ke_io,
};

fn stateOf(self: *abi_text.ke_font_loader) *State {
    return @fieldParentPtr("api", self);
}

/// Frees the loader that `ke_font_loader_stb_create` allocated. A null loader is ignored. Fonts
/// already loaded are separate allocations and stay valid until freed.
fn destroy(self: ?*abi_text.ke_font_loader) callconv(.c) void {
    const loader = self orelse return;
    gpa.destroy(stateOf(loader));
}

/// The whole file at `path`, released with the io's `free_bytes`. Fails with io when it cannot be
/// read or is empty, and with out of memory when the request cannot be allocated.
fn readFile(io: *abi_io.ke_io, path: [*c]const u8) R.Error![]const u8 {
    var request: ?*abi_io.ke_io_request = null;
    try R.check(io.read_file.?(io, path, &request));
    var file: abi_io.ke_io_result = undefined;
    R.check(io.wait.?(io, request, &file)) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return error.Io,
    };
    const bytes = file.bytes orelse return error.Io;
    if (file.size == 0) {
        io.free_bytes.?(io, bytes);
        return error.Io;
    }
    return @as([*]const u8, @ptrCast(bytes))[0..@intCast(file.size)];
}

/// Runs in the `load_font` slot, on the calling thread. On success the caller owns `out_font.*`
/// and releases it through `free_font`; on failure it is null and nothing `bake` allocated
/// survives.
fn loadFont(
    self: ?*abi_text.ke_font_loader,
    path: [*c]const u8,
    pixel_size: f32,
    first_codepoint: u32,
    codepoint_count: u32,
    atlas_size: u32,
    out_font: ?*[*c]abi_text.ke_font_data,
) callconv(.c) abi_result.ke_result {
    const out = out_font orelse return R.code(error.InvalidArgument);
    out.* = null;
    if (self == null or path == null) return R.code(error.InvalidArgument);
    out.* = bake(stateOf(self.?).io, path, pixel_size, first_codepoint, codepoint_count, atlas_size) catch |err| {
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
fn bake(io: *abi_io.ke_io, path: [*c]const u8, pixel_size: f32, first_codepoint: u32, codepoint_count: u32, atlas_size: u32) R.Error!*abi_text.ke_font_data {
    if (pixel_size <= 0.0 or atlas_size == 0 or codepoint_count == 0) return error.InvalidArgument;

    const ttf = try readFile(io, path);
    defer io.free_bytes.?(io, @constCast(ttf.ptr));

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

    const glyphs = gpa.alloc(abi_text.ke_glyph_metrics, codepoint_count) catch return error.OutOfMemory;
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

    const fd = gpa.create(abi_text.ke_font_data) catch return error.OutOfMemory;
    fd.* = .{
        .atlas_rgba = @ptrCast(atlas_rgba.ptr),
        .atlas_byte_count = @intCast(atlas_rgba.len),
        .atlas_width = w,
        .atlas_height = h,
        .glyphs = glyphs.ptr,
        .glyph_count = codepoint_count,
        .line_height = line_h,
        .ascent = ascent,
    };
    return fd;
}

/// Runs in the `free_font` slot. It sizes the atlas and glyph arrays from `atlas_byte_count` and
/// `glyph_count`, so those fields must still hold what `loadFont` wrote.
fn freeFont(self: ?*abi_text.ke_font_loader, data: [*c]abi_text.ke_font_data) callconv(.c) void {
    _ = self;
    if (data == null) return;
    const d: *abi_text.ke_font_data = @ptrCast(data);
    if (d.atlas_rgba != null) {
        gpa.free(@as([*]u8, @ptrCast(d.atlas_rgba))[0..d.atlas_byte_count]);
    }
    if (d.glyphs != null) {
        gpa.free(@as([*]abi_text.ke_glyph_metrics, @ptrCast(d.glyphs))[0..d.glyph_count]);
    }
    gpa.destroy(d);
}

/// Allocates the loader and fills the `load_font` and `free_font` slots; the handle's `destroy`
/// releases it. Fails with out of memory when it cannot be allocated, leaving the handle zeroed.
export fn ke_font_loader_stb_create(io_in: ?*abi_io.ke_io, out_loader: ?*abi_text.ke_font_loader_handle) callconv(.c) abi_result.ke_result {
    const out = out_loader orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const io = io_in orelse return R.code(error.InvalidArgument);
    const state = gpa.create(State) catch {
        log.warn("creating the font loader failed: out of memory", .{});
        return R.code(error.OutOfMemory);
    };
    state.* = .{ .api = .{ .handle = state, .load_font = &loadFont, .free_font = &freeFont }, .io = io };
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

const zsub = @import("zsub");

var served: ?[]const u8 = null;
var request_token: u8 = 0;

fn readServed(args: zsub.For(abi_io.ke_io).Args(.read_file)) abi_result.ke_result {
    args[2].?.* = @ptrCast(&request_token);
    return R.ok;
}

fn waitServed(args: zsub.For(abi_io.ke_io).Args(.wait)) abi_result.ke_result {
    const bytes = served orelse return R.code(error.NotFound);
    if (args[2]) |out| {
        out.* = std.mem.zeroes(abi_io.ke_io_result);
        out.bytes = @constCast(bytes.ptr);
        out.size = bytes.len;
    }
    return R.ok;
}

fn freeServed(_: zsub.For(abi_io.ke_io).Args(.free_bytes)) void {}

/// A substitute io serving `bytes` for every path, or no file at all when `bytes` is null.
const ServedIo = struct {
    sub: zsub.For(abi_io.ke_io),

    fn init(self: *ServedIo, bytes: ?[]const u8) !void {
        served = bytes;
        try self.sub.init();
        _ = self.sub.when(.read_file).does(readServed);
        _ = self.sub.when(.wait).does(waitServed);
        _ = self.sub.when(.free_bytes).does(freeServed);
    }

    fn deinit(self: *ServedIo) void {
        self.sub.deinit();
    }

    fn loader(self: *ServedIo) !abi_text.ke_font_loader_handle {
        var h: abi_text.ke_font_loader_handle = undefined;
        try R.check(ke_font_loader_stb_create(self.sub.api(), &h));
        return h;
    }
};

/// The bytes of the first candidate font the machine has, owned by the caller; null when none.
fn systemFont() ?[]u8 {
    for (font_candidates) |path| {
        const fp = libc.fopen(path, "rb") orelse continue;
        defer _ = libc.fclose(fp);
        _ = libc.fseek(fp, 0, libc.SEEK_END);
        const size = libc.ftell(fp);
        _ = libc.fseek(fp, 0, libc.SEEK_SET);
        if (size <= 0) continue;
        const buf = gpa.alloc(u8, @intCast(size)) catch return null;
        if (libc.fread(buf.ptr, 1, buf.len, fp) == buf.len) return buf;
        gpa.free(buf);
    }
    return null;
}

test "loading a font from a null path fails" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = try served_io.loader();
    defer h.destroy.?(h.ref);

    var data: [*c]abi_text.ke_font_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.load_font.?(h.ref, null, 16.0, 32, 96, 512, &data)));
    try testing.expect(data == null);
}

test "loading a font with a zero pixel size fails" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = try served_io.loader();
    defer h.destroy.?(h.ref);

    var data: [*c]abi_text.ke_font_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.load_font.?(h.ref, "test.ttf", 0.0, 32, 96, 512, &data)));
    try testing.expect(data == null);
}

test "loading a font with a negative pixel size fails" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = try served_io.loader();
    defer h.destroy.?(h.ref);

    var data: [*c]abi_text.ke_font_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.load_font.?(h.ref, "test.ttf", -1.0, 32, 96, 512, &data)));
    try testing.expect(data == null);
}

test "loading a font with a zero codepoint count fails" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = try served_io.loader();
    defer h.destroy.?(h.ref);

    var data: [*c]abi_text.ke_font_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.load_font.?(h.ref, "test.ttf", 16.0, 32, 0, 512, &data)));
    try testing.expect(data == null);
}

test "loading a font with a zero atlas size fails" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = try served_io.loader();
    defer h.destroy.?(h.ref);

    var data: [*c]abi_text.ke_font_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.load_font.?(h.ref, "test.ttf", 16.0, 32, 96, 0, &data)));
    try testing.expect(data == null);
}

test "loading a real system font produces an atlas with every requested glyph" {
    const font = systemFont() orelse return error.SkipZigTest;
    defer gpa.free(font);
    var served_io: ServedIo = undefined;
    try served_io.init(font);
    defer served_io.deinit();
    const h = try served_io.loader();
    defer h.destroy.?(h.ref);

    var data: [*c]abi_text.ke_font_data = null;
    try R.check(h.ref.?.load_font.?(h.ref, "font.ttf", 16.0, 32, 96, 512, &data));
    defer h.ref.?.free_font.?(h.ref, data);
    try testing.expectEqual(@as(u32, 96), data.*.glyph_count);
    try testing.expect(data.*.atlas_rgba != null);
}

test "loading a font file that does not exist fails with io" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = try served_io.loader();
    defer h.destroy.?(h.ref);

    var data: [*c]abi_text.ke_font_data = null;
    try testing.expectError(error.Io, R.check(h.ref.?.load_font.?(h.ref, "missing.ttf", 16.0, 32, 96, 512, &data)));
    try testing.expect(data == null);
}

test "creating without an io is refused and leaves the handle zeroed" {
    var h: abi_text.ke_font_loader_handle = .{ .ref = null, .destroy = null };
    try testing.expectError(error.InvalidArgument, R.check(ke_font_loader_stb_create(null, &h)));
    try testing.expect(h.ref == null);
}

test "destroying a null loader is a no-op" {
    destroy(null);
}

test "creating and destroying the font loader leaves no block allocated" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = try served_io.loader();
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}
