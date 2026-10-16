//! Downloads one file published outside any archive, which the build manifest cannot fetch, and
//! writes it only when its SHA-256 is the pinned one: `fetch_file <url> <sha256> <output>`.

const std = @import("std");

const Sha256 = std.crypto.hash.sha2.Sha256;

/// Exits 0 with the file written, 1 when the download or the digest fails, 2 on wrong arguments.
pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4) {
        std.debug.print("usage: fetch_file <url> <sha256> <output>\n", .{});
        return 2;
    }
    const url = args[1];
    const expected = args[2];

    var client: std.http.Client = .{ .allocator = arena, .io = init.io };
    defer client.deinit();
    var body: std.Io.Writer.Allocating = .init(arena);
    const result = client.fetch(.{ .location = .{ .url = url }, .response_writer = &body.writer }) catch |err| {
        std.debug.print("{s}: {s}\n", .{ url, @errorName(err) });
        return 1;
    };
    if (result.status != .ok) {
        std.debug.print("{s}: HTTP {d}\n", .{ url, @intFromEnum(result.status) });
        return 1;
    }
    const bytes = body.written();

    var digest: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(bytes, &digest, .{});
    const actual = std.fmt.bytesToHex(digest, .lower);
    if (!std.mem.eql(u8, &actual, expected)) {
        std.debug.print("{s}: sha256 {s}, expected {s}\n", .{ url, &actual, expected });
        return 1;
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[3], .data = bytes });
    return 0;
}
