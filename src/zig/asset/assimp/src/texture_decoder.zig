//! Turns a texture of a model, from an image file or embedded in the model, into the pixels of a
//! `ke_texture_data` that owns them.

const std = @import("std");

const c = @import("c");
const log = @import("log.zig");

/// Alignment of every pixel buffer this file allocates.
pub const pixel_align: std.mem.Alignment = .@"4";

/// Releases the pixels of one record with the length it declares. A record with no pixels, left
/// by a decode that ran out of memory, is skipped.
pub fn freePixels(gpa: std.mem.Allocator, tex: *const c.ke_texture_data) void {
    const px = tex.pixels orelse return;
    const base: [*]align(4) u8 = @ptrCast(@alignCast(px));
    gpa.free(base[0..tex.byte_count]);
}

/// Stands in for a decode that failed, so the record still has pixels. It returns true when the
/// white texel was allocated, which makes the fallback look like a successful decode to the caller.
fn fallbackWhite(gpa: std.mem.Allocator, logger: ?*c.ke_logger, out: *c.ke_texture_data) bool {
    log.warn(logger, "Failed to load texture; using white fallback");
    const px = gpa.alignedAlloc(u8, pixel_align, 4) catch return false;
    @memset(px, 0xFF);
    out.pixels = px.ptr;
    out.byte_count = 4;
    out.width = 1;
    out.height = 1;
    return true;
}

/// Moves decoder-owned RGBA pixels into a buffer the record owns, and fills the record's size.
/// Returns false when that buffer cannot be allocated. The decoder's buffer stays the caller's.
fn copyToOwnStorage(gpa: std.mem.Allocator, raw: [*]const u8, w: c_int, h: c_int, out: *c.ke_texture_data) bool {
    const byte_count = @as(usize, @intCast(w)) * @as(usize, @intCast(h)) * 4;
    const px = gpa.alignedAlloc(u8, pixel_align, byte_count) catch return false;
    @memcpy(px, raw[0..byte_count]);
    out.pixels = px.ptr;
    out.byte_count = @intCast(byte_count);
    out.width = @intCast(w);
    out.height = @intCast(h);
    return true;
}

/// Called by `loadModel` for each texture that names a file, and for an embedded name whose index
/// did not resolve: that call passes an empty path, and the decode falls back. A decode that
/// fails is absorbed by `fallbackWhite`, so a bad texture does not fail the model. The record's
/// path is
/// set before the pixels are allocated, so an allocation failure leaves a path with no pixels.
/// Returns false only when that allocation fails.
pub fn decodeExternal(gpa: std.mem.Allocator, path: [*:0]const u8, logger: ?*c.ke_logger, out: *c.ke_texture_data) bool {
    var w: c_int = 0;
    var h: c_int = 0;
    var ch: c_int = 0;
    const raw = c.stbi_load(path, &w, &h, &ch, 4) orelse return fallbackWhite(gpa, logger, out);
    log.copyString(&out.path, path);
    const ok = copyToOwnStorage(gpa, raw, w, h, out);
    c.stbi_image_free(raw);
    return ok;
}

/// Called by `loadModel` for an embedded texture whose index resolved to a texture of the scene. A
/// texture of zero height is compressed and is decoded with the same fallback as `decodeExternal`;
/// any other texture is copied as it is, without decoding. Allocation failure makes either return
/// false.
pub fn decodeEmbedded(gpa: std.mem.Allocator, et: *const c.aiTexture, logger: ?*c.ke_logger, out: *c.ke_texture_data) bool {
    if (et.mHeight == 0) {
        var w: c_int = 0;
        var h: c_int = 0;
        var ch: c_int = 0;
        const raw = c.stbi_load_from_memory(
            @ptrCast(et.pcData),
            @intCast(et.mWidth),
            &w,
            &h,
            &ch,
            4,
        ) orelse return fallbackWhite(gpa, logger, out);
        const ok = copyToOwnStorage(gpa, raw, w, h, out);
        c.stbi_image_free(raw);
        return ok;
    }

    const w: usize = @intCast(et.mWidth);
    const h: usize = @intCast(et.mHeight);
    const count = w * h;
    const px = gpa.alignedAlloc(u8, pixel_align, count * 4) catch return false;
    const src = et.pcData;
    for (0..count) |i| {
        px[i * 4 + 0] = src[i].r;
        px[i * 4 + 1] = src[i].g;
        px[i * 4 + 2] = src[i].b;
        px[i * 4 + 3] = src[i].a;
    }
    out.pixels = px.ptr;
    out.byte_count = @intCast(px.len);
    out.width = @intCast(w);
    out.height = @intCast(h);
    return true;
}
