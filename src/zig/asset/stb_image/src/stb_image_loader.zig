const std = @import("std");

// dlopen'd by a foreign (non-Zig) host (the C# runtime) alongside many other
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack blows the small glibc static-TLS surplus once enough accumulate
// (verified: "cannot allocate memory in static TLS block"); the extra crash-
// handler stack trace it buys isn't worth an unloadable plugin.
pub const std_options: std.Options = .{ .signal_stack_size = null };

const gpa = std.heap.c_allocator;

// Declarations only — the implementation is compiled as C from
// stb_image_impl.c (see build.zig); translate-c cannot reliably lower
// stb_image's JPEG decoder, so @cImport never sees STB_IMAGE_IMPLEMENTATION.
const stb = @cImport({
    @cInclude("stb_image.h");
});

const c = @cImport({
    @cInclude("kernel_engine/asset/stb_image/stb_image_loader.h");
    @cInclude("kernel_engine/logger/logger.h");
});

// Zig-native error translation at the C-ABI seam (no ke_common link).
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
    // Force RGBA8 — matches ke_texture_data's contract (4 bytes/pixel, row-major).
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
        const pixel_bytes: usize = @as(usize, d.width) * @as(usize, d.height) * 4;
        gpa.free(@as([*]u8, @ptrCast(d.pixels))[0..pixel_bytes]);
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
