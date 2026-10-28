//! Reads what the build wrote beside a compiled shader: the compiled code a device loads and the
//! reflection a binder builds layouts from.

const std = @import("std");
const c = @import("c");

const log = std.log.scoped(.shader_files);

/// The whole contents of the file at `path`, owned by the caller and freed with `gpa`. Fails
/// as not found when the file does not open, I/O when it cannot be sized or fully read, out
/// of memory when the buffer cannot be allocated; the reason is logged.
pub fn read(gpa: std.mem.Allocator, path: [:0]const u8) error{ NotFound, Io, OutOfMemory }![]u8 {
    const fp = c.fopen(path.ptr, "rb") orelse {
        log.warn("shader file not found: {s}", .{path});
        return error.NotFound;
    };
    defer _ = c.fclose(fp);
    _ = c.fseek(fp, 0, c.SEEK_END);
    const size_signed = c.ftell(fp);
    _ = c.fseek(fp, 0, c.SEEK_SET);
    if (size_signed < 0) {
        log.warn("failed to size shader file: {s}", .{path});
        return error.Io;
    }
    const size: usize = @intCast(size_signed);
    const bytes = try gpa.alloc(u8, size);
    if (c.fread(bytes.ptr, 1, size, fp) != size) {
        log.warn("failed to read shader file: {s}", .{path});
        gpa.free(bytes);
        return error.Io;
    }
    return bytes;
}
