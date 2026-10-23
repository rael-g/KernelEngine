//! Implements the `ke_image_loader` contract on stb_image: it decodes an image file to RGBA
//! pixels and frees the result.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_asset_stb_image").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const heap = @import("heap");
const gpa = heap.gpa;

const stb = @import("c");

const c = @import("c");

const R = @import("result").Result(c, .{});

const log = std.log.scoped(.asset_stb_image);

/// The loader: the vtable the handle refers to, whose `handle` points back at the state. It holds
/// nothing else, since a decode needs only its path.
const State = struct {
    api: c.ke_image_loader,
};

fn stateOf(self: *c.ke_image_loader) *State {
    return @fieldParentPtr("api", self);
}

/// The handle's `destroy`: releases the loader. A null loader is ignored.
fn destroy(self: ?*c.ke_image_loader) callconv(.c) void {
    const loader = self orelse return;
    gpa.destroy(stateOf(loader));
}

/// Called through the `load_image` slot. A decode failure logs stb's failure reason and fails with
/// not found; an allocation failure fails with out of memory. Either way nothing is left allocated
/// and the image written is null. On success the result owns a copy of the pixels, independent of
/// stb_image's allocator, and its path field holds the path truncated to fit; it is released
/// through `freeImage`. The call runs on the calling thread.
fn loadImage(self: ?*c.ke_image_loader, path: [*c]const u8, out_image: ?*[*c]c.ke_texture_data) callconv(.c) c.ke_result {
    const out = out_image orelse return R.code(error.InvalidArgument);
    out.* = null;
    if (self == null or path == null) return R.code(error.InvalidArgument);
    out.* = decode(path) catch |err| return R.code(err);
    return R.ok;
}

fn decode(path: [*c]const u8) R.Error!*c.ke_texture_data {
    var w: c_int = 0;
    var h: c_int = 0;
    var channels: c_int = 0;
    const raw = stb.stbi_load(path, &w, &h, &channels, 4);
    if (raw == null) {
        log.warn("{s}: {s}", .{ path, stb.stbi_failure_reason() });
        return error.NotFound;
    }
    defer stb.stbi_image_free(raw);

    const pixel_bytes: usize = @as(usize, @intCast(w)) * @as(usize, @intCast(h)) * 4;

    const data = gpa.create(c.ke_texture_data) catch return error.OutOfMemory;
    errdefer gpa.destroy(data);
    data.* = std.mem.zeroes(c.ke_texture_data);

    const pixels = gpa.alloc(u8, pixel_bytes) catch return error.OutOfMemory;
    @memcpy(pixels, @as([*]const u8, @ptrCast(raw))[0..pixel_bytes]);

    data.pixels = pixels.ptr;
    data.byte_count = @intCast(pixel_bytes);
    data.width = @intCast(w);
    data.height = @intCast(h);

    const path_slice = std.mem.span(path);
    const cap = @sizeOf(@TypeOf(data.path)) - 1;
    const n = @min(path_slice.len, cap);
    @memcpy(data.path[0..n], path_slice[0..n]);
    @memset(data.path[n .. n + 1], 0);

    return data;
}

/// Called through the `free_image` slot on a result of `loadImage`. The pixel buffer is released
/// with the length `loadImage` recorded in `byte_count`, which is the length it was allocated with.
fn freeImage(self: ?*c.ke_image_loader, data: [*c]c.ke_texture_data) callconv(.c) void {
    if (self == null or data == null) return;
    const d: *c.ke_texture_data = @ptrCast(data);
    if (d.pixels != null) {
        gpa.free(@as([*]u8, @ptrCast(d.pixels))[0..d.byte_count]);
    }
    gpa.destroy(d);
}

/// The exported factory. On success the handle's `ref` is the loader with both slots wired and
/// its `destroy` releases it; when the loader cannot be allocated it fails with out of memory and
/// the handle stays zeroed.
export fn ke_image_loader_stb_create(out_loader: ?*c.ke_image_loader_handle) callconv(.c) c.ke_result {
    const out = out_loader orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const state = gpa.create(State) catch {
        log.warn("creating the image loader failed: out of memory", .{});
        return R.code(error.OutOfMemory);
    };
    state.* = .{ .api = .{ .handle = state, .load_image = &loadImage, .free_image = &freeImage } };
    out.* = .{ .ref = &state.api, .destroy = &destroy };
    return R.ok;
}

const testing = std.testing;

const testing_libc = @import("c");

fn createLoader() c.ke_image_loader_handle {
    var h: c.ke_image_loader_handle = .{ .ref = null, .destroy = null };
    _ = ke_image_loader_stb_create(&h);
    return h;
}

test "creating the loader wires up a handle with every vtable slot filled" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.handle != null);
    try testing.expect(h.destroy != null);
    try testing.expect(h.ref.*.load_image != null);
}

test "loading an image with a null loader or a null path fails" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    var data: [*c]c.ke_texture_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.*.load_image.?(null, "path", &data)));
    try testing.expectError(error.InvalidArgument, R.check(h.ref.*.load_image.?(h.ref, null, &data)));
    try testing.expect(data == null);
}

test "freeing a null image is a no-op" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    h.ref.*.free_image.?(h.ref, null);
    h.ref.*.free_image.?(null, null);
}

test "loading a one pixel targa yields its dimensions and pixels" {
    const tga = [_]u8{
        0,   0,   2,  0,   0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 32, 0,
        255, 128, 64, 255,
    };

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_len = try tmp.dir.realPath(testing.io, &dir_buf);
    const dir_path = dir_buf[0..dir_len];

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&path_buf, "{s}/test_image.tga", .{dir_path});

    const fp = testing_libc.fopen(path.ptr, "wb") orelse return error.FixtureWriteFailed;
    const written = testing_libc.fwrite(&tga, 1, tga.len, fp);
    _ = testing_libc.fclose(fp);
    try testing.expectEqual(@as(usize, tga.len), written);

    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    var data: [*c]c.ke_texture_data = null;
    try R.check(h.ref.*.load_image.?(h.ref, path.ptr, &data));
    try testing.expect(data != null);
    defer h.ref.*.free_image.?(h.ref, data);

    try testing.expectEqual(@as(u32, 1), data.*.width);
    try testing.expectEqual(@as(u32, 1), data.*.height);
    try testing.expect(data.*.pixels != null);
}

test "destroying a null loader is a no-op" {
    destroy(null);
}

test "creating and destroying the image loader leaves no block allocated" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}
