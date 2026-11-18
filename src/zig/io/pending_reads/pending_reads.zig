//! Reads of whole files kept by path, so a thread that may not wait on a `ke_io` starts a read and
//! collects it on a later call instead.

const std = @import("std");
const abi_io = @import("abi_io");

const R = @import("result").Result(.{});

/// The reads of whole files an object keeps by path, so a thread that may not wait on the
/// io starts a read and collects it on a later call. An entry holds its text or its failure until
/// `forget`, and is freed only by `deinit`. The thread that sets an entry's `taken` from false owns
/// its `request`, `text` and `failure` until it clears `taken`.
pub const Reads = struct {
    gpa: std.mem.Allocator,
    head: std.atomic.Value(?*Entry) = .init(null),

    const Entry = struct {
        next: ?*Entry,
        path: [:0]u8,
        taken: std.atomic.Value(bool),
        request: ?*abi_io.c.ke_io_request,
        text: ?[:0]u8,
        failure: ?R.Error,
    };

    fn find(self: *Reads, path: []const u8) ?*Entry {
        var it = self.head.load(.acquire);
        while (it) |entry| : (it = entry.next) {
            if (std.mem.eql(u8, entry.path, path)) return entry;
        }
        return null;
    }

    fn add(self: *Reads, path: []const u8) R.Error!*Entry {
        const entry = try self.gpa.create(Entry);
        errdefer self.gpa.destroy(entry);
        entry.* = .{ .next = null, .path = try self.gpa.dupeZ(u8, path), .taken = .init(false), .request = null, .text = null, .failure = null };
        var head = self.head.load(.monotonic);
        while (true) {
            entry.next = head;
            head = self.head.cmpxchgWeak(head, entry, .release, .monotonic) orelse break;
        }
        return entry;
    }

    /// The whole file at `path` with a terminating zero, owned by the reads until `forget`. Fails as
    /// pending while the read goes on or another thread collects it, and with the read's error,
    /// kept until `forget`, when it failed.
    pub fn text(self: *Reads, io: *abi_io.c.ke_io, path: [*:0]const u8) R.Error![:0]const u8 {
        const span = std.mem.span(path);
        const entry = self.find(span) orelse try self.add(span);
        if (entry.taken.cmpxchgStrong(false, true, .acquire, .monotonic) != null) return error.Pending;
        defer entry.taken.store(false, .release);
        if (entry.text) |t| return t;
        if (entry.failure) |err| return err;
        if (entry.request == null) R.check(io.read_file.?(io, path, &entry.request)) catch |err| {
            entry.failure = err;
            return err;
        };
        var result: abi_io.c.ke_io_result = undefined;
        const code = io.wait.?(io, entry.request, &result);
        if (code == R.code(error.NotSupported)) return error.Pending;
        entry.request = null;
        R.check(code) catch |err| {
            entry.failure = err;
            return err;
        };
        defer io.free_bytes.?(io, result.bytes);
        const bytes: []const u8 = if (result.bytes) |b| @as([*]const u8, @ptrCast(b))[0..@intCast(result.size)] else "";
        entry.text = try self.gpa.dupeZ(u8, bytes);
        return entry.text.?;
    }

    /// Drops the text or the failure kept for `path`, so the next `text` reads the file again. A path
    /// being read, or collected by another thread, is left as it is.
    pub fn forget(self: *Reads, path: []const u8) void {
        const entry = self.find(path) orelse return;
        if (entry.taken.cmpxchgStrong(false, true, .acquire, .monotonic) != null) return;
        defer entry.taken.store(false, .release);
        if (entry.text) |t| self.gpa.free(t);
        entry.text = null;
        entry.failure = null;
    }

    /// Collects every read still in flight and frees every entry; called on the thread that may wait.
    pub fn deinit(self: *Reads, io: *abi_io.c.ke_io) void {
        var it = self.head.swap(null, .acquire);
        while (it) |entry| {
            it = entry.next;
            if (entry.request) |request| {
                var result: abi_io.c.ke_io_result = undefined;
                if (io.wait.?(io, request, &result) == R.ok) io.free_bytes.?(io, result.bytes);
            }
            if (entry.text) |t| self.gpa.free(t);
            self.gpa.free(entry.path);
            self.gpa.destroy(entry);
        }
    }
};

const testing = std.testing;
const abi_result = @import("abi_result");
const zsub = @import("zsub");
const IoSub = zsub.For(abi_io.c.ke_io);

var scene_bytes = "[scene]".*;
var request_token: u8 = 0;
var wait_refused = false;

fn submitRead(args: IoSub.Args(.read_file)) abi_result.c.ke_result {
    if (std.mem.eql(u8, std.mem.span(args[1].?), "missing")) return R.code(error.NotFound);
    args[2].?.* = @ptrCast(&request_token);
    return R.ok;
}

fn waitRead(args: IoSub.Args(.wait)) abi_result.c.ke_result {
    if (wait_refused) return R.code(error.NotSupported);
    args[2].?.* = std.mem.zeroes(abi_io.c.ke_io_result);
    args[2].?.bytes = &scene_bytes;
    args[2].?.size = scene_bytes.len;
    return R.ok;
}

test "a read the calling thread may not wait for is pending, then collected once, and read again after forget" {
    var io: IoSub = undefined;
    try io.init();
    defer io.deinit();
    _ = io.when(.read_file).does(submitRead);
    _ = io.when(.wait).does(waitRead);
    var reads: Reads = .{ .gpa = testing.allocator };
    defer reads.deinit(io.api());

    wait_refused = true;
    try testing.expectError(error.Pending, reads.text(io.api(), "a.scene"));
    wait_refused = false;
    try testing.expectEqualStrings("[scene]", try reads.text(io.api(), "a.scene"));
    try testing.expectEqualStrings("[scene]", try reads.text(io.api(), "a.scene"));
    try io.received(.read_file).times(1);

    reads.forget("a.scene");
    _ = try reads.text(io.api(), "a.scene");
    try io.received(.read_file).times(2);
}

test "a read that failed keeps its failure until forget" {
    var io: IoSub = undefined;
    try io.init();
    defer io.deinit();
    _ = io.when(.read_file).does(submitRead);
    _ = io.when(.wait).does(waitRead);
    var reads: Reads = .{ .gpa = testing.allocator };
    defer reads.deinit(io.api());

    try testing.expectError(error.NotFound, reads.text(io.api(), "missing"));
    try testing.expectError(error.NotFound, reads.text(io.api(), "missing"));
    try io.received(.read_file).times(1);
    reads.forget("missing");
    try testing.expectError(error.NotFound, reads.text(io.api(), "missing"));
    try io.received(.read_file).times(2);
}

test "reading, collecting and freeing leaves no block allocated" {
    var io: IoSub = undefined;
    try io.init();
    defer io.deinit();
    _ = io.when(.read_file).does(submitRead);
    _ = io.when(.wait).does(waitRead);
    var reads: Reads = .{ .gpa = testing.allocator };
    wait_refused = true;
    _ = reads.text(io.api(), "pending") catch {};
    wait_refused = false;
    _ = try reads.text(io.api(), "kept");
    reads.deinit(io.api());
}
