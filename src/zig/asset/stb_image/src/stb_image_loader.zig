const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const gpa = std.heap.c_allocator;

const stb = @cImport({
    @cInclude("stb_image.h");
});

const c = @cImport({
    @cInclude("kernel_engine/asset/stb_image/stb_image_loader.h");
    @cInclude("kernel_engine/logger/logger.h");
});

const E = @import("kerror").Errors(c);

const State = struct {
    logger: ?*c.ke_logger,
};

fn logWarn(logger: ?*c.ke_logger, msg: [*c]const u8) void {
    const lg = logger orelse return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_WARNING, .tag = "stb_image", .message = msg };
    lg.log.?(lg, &ev);
}

fn destroy(self: ?*c.ke_image_loader) callconv(.c) void {
    const loader = self orelse return;
    const state: *State = @ptrCast(@alignCast(loader.handle));
    gpa.destroy(state);
    gpa.destroy(loader);
}

fn loadImage(self: ?*c.ke_image_loader, path: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) [*c]c.ke_texture_data {
    if (self == null or path == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null;
    }
    const loader = self.?;
    const state: *State = @ptrCast(@alignCast(loader.handle));

    var w: c_int = 0;
    var h: c_int = 0;
    var channels: c_int = 0;
    const raw = stb.stbi_load(path, &w, &h, &channels, 4);
    if (raw == null) {
        logWarn(state.logger, stb.stbi_failure_reason());
        E.fail(out_error, .not_found, "image file not found or failed to decode", @src());
        return null;
    }
    defer stb.stbi_image_free(raw);

    const pixel_bytes: usize = @as(usize, @intCast(w)) * @as(usize, @intCast(h)) * 4;

    const data = gpa.create(c.ke_texture_data) catch {
        E.fail(out_error, .out_of_memory, "texture data allocation failed", @src());
        return null;
    };
    data.* = std.mem.zeroes(c.ke_texture_data);

    const pixels = gpa.alloc(u8, pixel_bytes) catch {
        gpa.destroy(data);
        E.fail(out_error, .out_of_memory, "pixel buffer allocation failed", @src());
        return null;
    };
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

fn freeImage(self: ?*c.ke_image_loader, data: [*c]c.ke_texture_data) callconv(.c) void {
    if (self == null or data == null) return;
    const d: *c.ke_texture_data = @ptrCast(data);
    if (d.pixels != null) {
        gpa.free(@as([*]u8, @ptrCast(d.pixels))[0..d.byte_count]);
    }
    gpa.destroy(d);
}

export fn ke_image_loader_stb_create(
    params: [*c]const c.ke_image_loader_stb_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_image_loader_handle {
    const empty = c.ke_image_loader_handle{ .ref = null, .destroy = null };
    if (params == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return empty;
    }

    const state = gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return empty;
    };
    state.* = .{ .logger = params.*.logger };

    const loader = gpa.create(c.ke_image_loader) catch {
        gpa.destroy(state);
        E.fail(out_error, .out_of_memory, "loader allocation failed", @src());
        return empty;
    };
    loader.handle = state;
    loader.load_image = &loadImage;
    loader.free_image = &freeImage;

    return .{ .ref = loader, .destroy = &destroy };
}

const testing = std.testing;

const testing_libc = @cImport({
    @cInclude("stdio.h");
});

fn createLoader() c.ke_image_loader_handle {
    var params = std.mem.zeroes(c.ke_image_loader_stb_params);
    return ke_image_loader_stb_create(&params, null);
}

test "creating the loader wires up a handle with every vtable slot filled" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.handle != null);
    try testing.expect(h.destroy != null);
    try testing.expect(h.ref.*.load_image != null);
}

test "creating the loader with null params returns a null handle" {
    const h = ke_image_loader_stb_create(null, null);
    try testing.expect(h.ref == null);
}

test "loading an image with a null loader or a null path fails" {
    const h = createLoader();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.load_image.?(null, "path", null) == null);
    try testing.expect(h.ref.*.load_image.?(h.ref, null, null) == null);
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

    const data = h.ref.*.load_image.?(h.ref, path.ptr, null);
    try testing.expect(data != null);
    defer h.ref.*.free_image.?(h.ref, data);

    try testing.expectEqual(@as(u32, 1), data.*.width);
    try testing.expectEqual(@as(u32, 1), data.*.height);
    try testing.expect(data.*.pixels != null);
}

test "destroying a null loader is a no-op" {
    destroy(null);
}
