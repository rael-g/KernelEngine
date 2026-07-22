// Texture decoding for the assimp loader.
//
// Heap ownership rule, carried over from the C++ implementation: out.pixels is
// ALWAYS allocated by this plugin's own allocator, and any intermediate buffer
// is released with its own producer's free (stb's buffers with
// stbi_image_free). Mixing heaps across a shared-library boundary crashes on
// Windows, where each CRT owns its own.
//
// Pixel buffers stay 4-byte aligned so a texel is never split across the
// granularity a GPU upload copies in.

const std = @import("std");

const c = @import("c.zig").c;
const log = @import("log.zig");

/// Alignment every pixel buffer here is allocated with; `freePixels` must be
/// given the same one or the allocator cannot match the block.
pub const pixel_align: std.mem.Alignment = .@"4";

/// Releases a buffer produced by this module. The size is recovered from the
/// dimensions the texture record already carries, which is exactly the count
/// that was allocated.
pub fn freePixels(gpa: std.mem.Allocator, tex: *const c.ke_texture_data) void {
    const px = tex.pixels orelse return;
    const n = @as(usize, tex.width) * @as(usize, tex.height) * 4;
    const base: [*]align(4) u8 = @ptrCast(@alignCast(px));
    gpa.free(base[0..n]);
}

/// A texture that fails to load becomes an opaque white 1x1 rather than a hole,
/// so a missing file degrades to an unlit surface instead of failing the model.
fn fallbackWhite(gpa: std.mem.Allocator, logger: ?*c.ke_logger, out: *c.ke_texture_data) bool {
    log.warn(logger, "Failed to load texture; using white fallback");
    const px = gpa.alignedAlloc(u8, pixel_align, 4) catch return false;
    @memset(px, 0xFF);
    out.pixels = px.ptr;
    out.width = 1;
    out.height = 1;
    return true;
}

fn copyToOwnStorage(gpa: std.mem.Allocator, raw: [*]const u8, w: c_int, h: c_int, out: *c.ke_texture_data) bool {
    const byte_count = @as(usize, @intCast(w)) * @as(usize, @intCast(h)) * 4;
    const px = gpa.alignedAlloc(u8, pixel_align, byte_count) catch return false;
    @memcpy(px, raw[0..byte_count]);
    out.pixels = px.ptr;
    out.width = @intCast(w);
    out.height = @intCast(h);
    return true;
}

pub fn decodeExternal(gpa: std.mem.Allocator, path: [*:0]const u8, logger: ?*c.ke_logger, out: *c.ke_texture_data) bool {
    var w: c_int = 0;
    var h: c_int = 0;
    var ch: c_int = 0;
    const raw = c.stbi_load(path, &w, &h, &ch, 4) orelse return fallbackWhite(gpa, logger, out);
    log.copyString(&out.path, path);
    const ok = copyToOwnStorage(gpa, raw, w, h, out);
    c.stbi_image_free(raw); // matched with stbi_load
    return ok;
}

pub fn decodeEmbedded(gpa: std.mem.Allocator, et: *const c.aiTexture, logger: ?*c.ke_logger, out: *c.ke_texture_data) bool {
    if (et.mHeight == 0) {
        // Compressed in memory (a PNG/JPEG inside a GLB); stb owns the decode
        // buffer, and mWidth is its byte length rather than a pixel count.
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
        c.stbi_image_free(raw); // matched with stbi_load_from_memory
        return ok;
    }

    // Uncompressed texels in assimp's buffer: written straight into the
    // destination, so no intermediate copy is needed.
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
    out.width = @intCast(w);
    out.height = @intCast(h);
    return true;
}
