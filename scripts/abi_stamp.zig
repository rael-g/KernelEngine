const std = @import("std");

const Sha256 = std.crypto.hash.sha2.Sha256;

pub const stamp_header = "ke-abi-stamp 1\n";

const read_limit: std.Io.Limit = .limited(16 * 1024 * 1024);

fn isContractHeader(path: []const u8) bool {
    if (!std.mem.endsWith(u8, path, ".h")) return false;
    if (std.mem.indexOf(u8, path, "third_party") != null) return false;
    if (std.mem.indexOf(u8, path, ".zig-cache") != null) return false;
    if (std.mem.startsWith(u8, path, "src/c/")) return true;
    return std.mem.startsWith(u8, path, "src/zig/") and std.mem.indexOf(u8, path, "/include/") != null;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

pub fn digestWithoutCarriageReturns(bytes: []const u8) [Sha256.digest_length]u8 {
    var hasher = Sha256.init(.{});
    var start: usize = 0;
    for (bytes, 0..) |byte, i| {
        if (byte != '\r') continue;
        hasher.update(bytes[start..i]);
        start = i + 1;
    }
    hasher.update(bytes[start..]);
    return hasher.finalResult();
}

pub fn compute(allocator: std.mem.Allocator, io: std.Io, repo_root: []const u8) ![]u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (paths.items) |p| allocator.free(p);
        paths.deinit(allocator);
    }

    var root = try std.Io.Dir.openDirAbsolute(io, repo_root, .{ .iterate = true });
    defer root.close(io);
    inline for (.{ "src/c", "src/zig" }) |sub| {
        var dir = try root.openDir(io, sub, .{ .iterate = true });
        defer dir.close(io);
        var walker = try dir.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            const rel = try std.fmt.allocPrint(allocator, sub ++ "/{s}", .{entry.path});
            errdefer allocator.free(rel);
            std.mem.replaceScalar(u8, rel, std.fs.path.sep, '/');
            if (!isContractHeader(rel)) {
                allocator.free(rel);
                continue;
            }
            try paths.append(allocator, rel);
        }
    }
    std.mem.sort([]const u8, paths.items, {}, lessThan);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, stamp_header);
    for (paths.items) |rel| {
        const bytes = try root.readFileAlloc(io, rel, allocator, read_limit);
        defer allocator.free(bytes);
        const digest = digestWithoutCarriageReturns(bytes);
        try out.print(allocator, "{x}  {s}\n", .{ digest, rel });
    }
    return out.toOwnedSlice(allocator);
}

const testing = std.testing;

test "the stamp lists contract and factory headers by path with a digest of each, and nothing else" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "src/c/dom/kernel_engine/dom");
    try tmp.dir.createDirPath(testing.io, "src/zig/dom/plug/include/kernel_engine/dom");
    try tmp.dir.createDirPath(testing.io, "src/zig/dom/plug/src");
    try tmp.dir.createDirPath(testing.io, "src/zig/dom/plug/third_party/lib/include");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "src/c/dom/kernel_engine/dom/a.h", .data = "int a;\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "src/zig/dom/plug/include/kernel_engine/dom/make.h", .data = "int make;\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "src/zig/dom/plug/src/internal.h", .data = "int internal;\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "src/zig/dom/plug/third_party/lib/include/vendored.h", .data = "int vendored;\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "src/zig/dom/plug/src/impl.zig", .data = "const x = 1;\n" });

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPathFile(testing.io, ".", &buf);
    const stamp = try compute(testing.allocator, testing.io, buf[0..len]);
    defer testing.allocator.free(stamp);

    try testing.expect(std.mem.startsWith(u8, stamp, stamp_header));
    try testing.expect(std.mem.indexOf(u8, stamp, "  src/c/dom/kernel_engine/dom/a.h\n") != null);
    try testing.expect(std.mem.indexOf(u8, stamp, "  src/zig/dom/plug/include/kernel_engine/dom/make.h\n") != null);
    try testing.expect(std.mem.indexOf(u8, stamp, "internal.h") == null);
    try testing.expect(std.mem.indexOf(u8, stamp, "vendored.h") == null);
    try testing.expect(std.mem.indexOf(u8, stamp, "impl.zig") == null);
}

test "a header's digest ignores its carriage returns and follows its content" {
    const unix = digestWithoutCarriageReturns("int a;\nint b;\n");
    const windows = digestWithoutCarriageReturns("int a;\r\nint b;\r\n");
    const changed = digestWithoutCarriageReturns("int a;\nint c;\n");
    try testing.expectEqualSlices(u8, &unix, &windows);
    try testing.expect(!std.mem.eql(u8, &unix, &changed));
}
