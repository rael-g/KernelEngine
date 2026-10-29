//! The aiFileIO an import opens its files through: the model and every file it names are read
//! whole through a ke_io, and Assimp reads them from memory.

const std = @import("std");
const c = @import("c");
const abi_io = @import("abi_io");

const R = @import("result").Result(.{});
const log = std.log.scoped(.asset_assimp);

const file_heap = std.heap.smp_allocator;

/// One file Assimp holds open: the bytes the io read, released through the same io on close, and
/// the cursor Assimp reads from. `file` is what Assimp is handed; its `UserData` points back here.
const OpenFile = struct {
    file: c.aiFile,
    io: *abi_io.ke_io,
    raw: ?*anyopaque,
    bytes: [*]const u8,
    size: usize,
    cursor: usize,
};

/// The bytes of the file at `path`, read whole through `io` and released with its `free_bytes`.
/// A file the io cannot read fails with the code the io reported.
pub fn readWhole(io: *abi_io.ke_io, path: [*:0]const u8) R.Error!abi_io.ke_io_result {
    var request: ?*abi_io.ke_io_request = null;
    try R.check(io.read_file.?(io, path, &request));
    var result: abi_io.ke_io_result = undefined;
    try R.check(io.wait.?(io, request, &result));
    return result;
}

/// The aiFileIO of one import over `io`, which is borrowed for as long as the import runs. A file
/// asked for writing is refused.
pub fn of(io: *abi_io.ke_io) c.aiFileIO {
    return .{ .OpenProc = open, .CloseProc = close, .UserData = @ptrCast(io) };
}

fn openOf(file: [*c]c.aiFile) *OpenFile {
    return @ptrCast(@alignCast(file.*.UserData));
}

fn open(file_io: [*c]c.aiFileIO, path: [*c]const u8, mode: [*c]const u8) callconv(.c) [*c]c.aiFile {
    if (file_io == null or path == null) return null;
    if (mode != null and std.mem.indexOfScalar(u8, std.mem.span(mode), 'w') != null) return null;
    const io: *abi_io.ke_io = @ptrCast(@alignCast(file_io.*.UserData));
    const read = readWhole(io, path) catch |err| {
        log.warn("reading {s} failed: {t}", .{ path, err });
        return null;
    };
    const opened = file_heap.create(OpenFile) catch {
        io.free_bytes.?(io, read.bytes);
        return null;
    };
    opened.* = .{
        .file = .{ .ReadProc = readProc, .WriteProc = writeProc, .TellProc = tell, .FileSizeProc = fileSize, .SeekProc = seek, .FlushProc = flush, .UserData = @ptrCast(opened) },
        .io = io,
        .raw = read.bytes,
        .bytes = if (read.bytes) |b| @ptrCast(b) else @as([*]const u8, &.{}),
        .size = @intCast(read.size),
        .cursor = 0,
    };
    return &opened.file;
}

fn close(file_io: [*c]c.aiFileIO, file: [*c]c.aiFile) callconv(.c) void {
    _ = file_io;
    if (file == null) return;
    const opened = openOf(file);
    if (opened.raw) |raw| opened.io.free_bytes.?(opened.io, raw);
    file_heap.destroy(opened);
}

fn readProc(file: [*c]c.aiFile, buffer: [*c]u8, size: usize, count: usize) callconv(.c) usize {
    if (file == null or buffer == null or size == 0) return 0;
    const opened = openOf(file);
    const items = @min(count, (opened.size - opened.cursor) / size);
    const n = items * size;
    @memcpy(buffer[0..n], opened.bytes[opened.cursor..][0..n]);
    opened.cursor += n;
    return items;
}

fn writeProc(file: [*c]c.aiFile, buffer: [*c]const u8, size: usize, count: usize) callconv(.c) usize {
    _ = .{ file, buffer, size, count };
    return 0;
}

fn tell(file: [*c]c.aiFile) callconv(.c) usize {
    return openOf(file).cursor;
}

fn fileSize(file: [*c]c.aiFile) callconv(.c) usize {
    return openOf(file).size;
}

fn seek(file: [*c]c.aiFile, offset: usize, origin: c.aiOrigin) callconv(.c) c.aiReturn {
    const opened = openOf(file);
    const base: usize = switch (origin) {
        c.aiOrigin_SET => 0,
        c.aiOrigin_CUR => opened.cursor,
        c.aiOrigin_END => opened.size,
        else => return c.aiReturn_FAILURE,
    };
    const target = std.math.add(usize, base, offset) catch return c.aiReturn_FAILURE;
    if (target > opened.size) return c.aiReturn_FAILURE;
    opened.cursor = target;
    return c.aiReturn_SUCCESS;
}

fn flush(file: [*c]c.aiFile) callconv(.c) void {
    _ = file;
}
