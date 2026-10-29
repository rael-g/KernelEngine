//! Implements the `ke_image_loader` contract on stb_image: it decodes an image file to RGBA
//! pixels and frees the result.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_asset_stb_image").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const heap = @import("heap");
const gpa = heap.gpa;

const stb = @import("c");
const abi_asset = @import("abi_asset");
const abi_io = @import("abi_io");
const abi_stb = @import("abi_asset_stb_image_factory");
const abi_result = @import("abi_result");

const R = @import("result").Result(.{});

const log = std.log.scoped(.asset_stb_image);

/// The loader: the vtable the handle refers to, whose `handle` points back at the state, and the
/// borrowed io every load reads its file through.
const State = struct {
    api: abi_asset.ke_image_loader,
    io: *abi_io.ke_io,
};

fn stateOf(self: *abi_asset.ke_image_loader) *State {
    return @fieldParentPtr("api", self);
}

/// The handle's `destroy`: releases the loader. A null loader is ignored.
fn destroy(self: ?*abi_asset.ke_image_loader) callconv(.c) void {
    const loader = self orelse return;
    gpa.destroy(stateOf(loader));
}

/// Called through the `load_image` slot. A file that cannot be read or decoded logs the reason and
/// fails with not found; an allocation failure fails with out of memory. Either way nothing is left allocated
/// and the image written is null. On success the result owns a copy of the pixels, independent of
/// stb_image's allocator, and its path field holds the path truncated to fit; it is released
/// through `freeImage`. The call runs on the calling thread.
fn loadImage(self: ?*abi_asset.ke_image_loader, path: [*c]const u8, out_image: ?*[*c]abi_asset.ke_texture_data) callconv(.c) abi_result.ke_result {
    const out = out_image orelse return R.code(error.InvalidArgument);
    out.* = null;
    if (self == null or path == null) return R.code(error.InvalidArgument);
    out.* = decode(stateOf(self.?).io, path) catch |err| return R.code(err);
    return R.ok;
}

fn decode(io: *abi_io.ke_io, path: [*c]const u8) R.Error!*abi_asset.ke_texture_data {
    var request: ?*abi_io.ke_io_request = null;
    try R.check(io.read_file.?(io, path, &request));
    var file: abi_io.ke_io_result = undefined;
    R.check(io.wait.?(io, request, &file)) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => {
            log.warn("reading {s} failed: {t}", .{ path, err });
            return error.NotFound;
        },
    };
    defer io.free_bytes.?(io, file.bytes);

    var w: c_int = 0;
    var h: c_int = 0;
    var channels: c_int = 0;
    const raw = stb.stbi_load_from_memory(@ptrCast(file.bytes), @intCast(file.size), &w, &h, &channels, 4);
    if (raw == null) {
        log.warn("{s}: {s}", .{ path, stb.stbi_failure_reason() });
        return error.NotFound;
    }
    defer stb.stbi_image_free(raw);

    const pixel_bytes: usize = @as(usize, @intCast(w)) * @as(usize, @intCast(h)) * 4;

    const data = gpa.create(abi_asset.ke_texture_data) catch return error.OutOfMemory;
    errdefer gpa.destroy(data);
    data.* = std.mem.zeroes(abi_asset.ke_texture_data);

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
fn freeImage(self: ?*abi_asset.ke_image_loader, data: [*c]abi_asset.ke_texture_data) callconv(.c) void {
    if (self == null or data == null) return;
    const d: *abi_asset.ke_texture_data = @ptrCast(data);
    if (d.pixels != null) {
        gpa.free(@as([*]u8, @ptrCast(d.pixels))[0..d.byte_count]);
    }
    gpa.destroy(d);
}

/// The exported factory. On success the handle's `ref` is the loader with both slots wired and
/// its `destroy` releases it; when the loader cannot be allocated it fails with out of memory and
/// the handle stays zeroed.
export fn ke_image_loader_stb_create(params: ?*const abi_stb.ke_image_loader_stb_params, out_loader: ?*abi_asset.ke_image_loader_handle) callconv(.c) abi_result.ke_result {
    const out = out_loader orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params orelse return R.code(error.InvalidArgument);
    const io = p.io orelse return R.code(error.InvalidArgument);
    const state = gpa.create(State) catch {
        log.warn("creating the image loader failed: out of memory", .{});
        return R.code(error.OutOfMemory);
    };
    state.* = .{ .api = .{ .handle = state, .load_image = &loadImage, .free_image = &freeImage }, .io = io };
    out.* = .{ .ref = &state.api, .destroy = &destroy };
    return R.ok;
}

const testing = std.testing;

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

    fn loader(self: *ServedIo) abi_asset.ke_image_loader_handle {
        var h: abi_asset.ke_image_loader_handle = .{ .ref = null, .destroy = null };
        _ = ke_image_loader_stb_create(&.{ .io = self.sub.api() }, &h);
        return h;
    }
};

test "creating the loader wires up a handle with every vtable slot filled" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.?.handle != null);
    try testing.expect(h.destroy != null);
    try testing.expect(h.ref.?.load_image != null);
}

test "loading an image with a null loader or a null path fails" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    var data: [*c]abi_asset.ke_texture_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.load_image.?(null, "path", &data)));
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.load_image.?(h.ref, null, &data)));
    try testing.expect(data == null);
}

test "freeing a null image is a no-op" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    h.ref.?.free_image.?(h.ref, null);
    h.ref.?.free_image.?(null, null);
}

test "loading a one pixel targa yields its dimensions and pixels" {
    const tga = [_]u8{
        0,   0,   2,  0,   0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 32, 0,
        255, 128, 64, 255,
    };

    var served_io: ServedIo = undefined;
    try served_io.init(&tga);
    defer served_io.deinit();
    const h = served_io.loader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    var data: [*c]abi_asset.ke_texture_data = null;
    try R.check(h.ref.?.load_image.?(h.ref, "test_image.tga", &data));
    try testing.expect(data != null);
    defer h.ref.?.free_image.?(h.ref, data);

    try testing.expectEqual(@as(u32, 1), data.*.width);
    try testing.expectEqual(@as(u32, 1), data.*.height);
    try testing.expect(data.*.pixels != null);
}

test "creating without an io is refused and leaves the handle zeroed" {
    var h: abi_asset.ke_image_loader_handle = .{ .ref = null, .destroy = null };
    try testing.expectError(error.InvalidArgument, R.check(ke_image_loader_stb_create(null, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_image_loader_stb_create(&.{}, &h)));
    try testing.expect(h.ref == null);
}

test "loading a file that does not exist fails with not found" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    defer h.destroy.?(h.ref);

    var data: [*c]abi_asset.ke_texture_data = null;
    try testing.expectError(error.NotFound, R.check(h.ref.?.load_image.?(h.ref, "missing.png", &data)));
    try testing.expect(data == null);
}

test "destroying a null loader is a no-op" {
    destroy(null);
}

test "creating and destroying the image loader leaves no block allocated" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}
