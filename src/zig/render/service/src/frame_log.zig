//! A list of entries the workers of a frame append to concurrently, read once the frame's passes
//! are done, and grown between frames to what the last frame asked for.

const std = @import("std");
const gpa = @import("heap").gpa;

/// Entries of type `T` claimed during a frame. A claim takes the next slot of `items` with an
/// atomic counter; once `items` is full it allocates a node of its own and links it onto `spill`
/// with a compare-and-swap, so no claim waits for another. `seal` puts the spilled nodes in claim
/// order and `reset` frees them and grows `items` to the count the frame reached, so the next frame
/// of that size does not spill. `seal`, `iterator` and `reset` run single-threaded, between frames.
pub fn FrameLog(comptime T: type) type {
    return struct {
        const Self = @This();

        const Spilled = struct { next: ?*Spilled, item: T };

        items: []T,
        blank: T,
        count: std.atomic.Value(u32) = .init(0),
        spill: std.atomic.Value(?*Spilled) = .init(null),
        sealed: ?*Spilled = null,

        /// A log with `first` slots, each and every later one starting as `blank`.
        pub fn init(first: usize, blank: T) error{OutOfMemory}!Self {
            const items = try gpa.alloc(T, first);
            @memset(items, blank);
            return .{ .items = items, .blank = blank };
        }

        /// Frees the slots and the spilled nodes, calling `finalize` on every entry first.
        pub fn deinit(self: *Self, finalize: ?*const fn (*T) void) void {
            self.reset(finalize);
            if (finalize) |f| for (self.items) |*it| f(it);
            gpa.free(self.items);
        }

        /// The next entry of the frame. A slot holds what the entry left in it last time, so the
        /// caller overwrites it; a spilled entry starts as `blank`. Callable from any worker. Null
        /// only when the slots are full and a node cannot be allocated.
        pub fn claim(self: *Self) ?*T {
            const at = self.count.fetchAdd(1, .monotonic);
            if (at < self.items.len) return &self.items[at];
            const node = gpa.create(Spilled) catch return null;
            node.* = .{ .next = null, .item = self.blank };
            var head = self.spill.load(.monotonic);
            while (true) {
                node.next = head;
                head = self.spill.cmpxchgWeak(head, node, .release, .monotonic) orelse return &node.item;
            }
        }

        /// Puts the spilled entries in the order they were claimed. Called once the frame's claims
        /// are done and before `iterator`.
        pub fn seal(self: *Self) void {
            var node = self.spill.swap(null, .acquire);
            while (node) |n| {
                node = n.next;
                n.next = self.sealed;
                self.sealed = n;
            }
        }

        /// Walks the frame's entries in claim order: the slots first, then the sealed nodes.
        pub fn iterator(self: *Self) Iterator {
            return .{ .items = self.items[0..@min(self.count.load(.monotonic), self.items.len)], .node = self.sealed };
        }

        pub const Iterator = struct {
            items: []T,
            at: usize = 0,
            node: ?*Spilled,

            pub fn next(it: *Iterator) ?*T {
                if (it.at < it.items.len) {
                    it.at += 1;
                    return &it.items[it.at - 1];
                }
                const n = it.node orelse return null;
                it.node = n.next;
                return &n.item;
            }
        };

        /// Ends the frame's log: frees the spilled nodes, calling `finalize` on their entries,
        /// grows the slots to the count the frame reached, and starts the count again. A failed
        /// growth keeps the slots it had, and the next frame of that size spills again.
        pub fn reset(self: *Self, finalize: ?*const fn (*T) void) void {
            self.seal();
            while (self.sealed) |n| {
                self.sealed = n.next;
                if (finalize) |f| f(&n.item);
                gpa.destroy(n);
            }
            const reached = self.count.swap(0, .monotonic);
            if (reached <= self.items.len) return;
            const old = self.items.len;
            const grown = gpa.realloc(self.items, std.math.ceilPowerOfTwoAssert(usize, reached)) catch return;
            @memset(grown[old..], self.blank);
            self.items = grown;
        }
    };
}

const testing = std.testing;

test "a frame that claims past the slots keeps every entry in claim order and grows for the next frame" {
    var log = try FrameLog(u32).init(2, 0);
    defer log.deinit(null);
    for (0..5) |i| log.claim().?.* = @intCast(i);
    log.seal();
    var it = log.iterator();
    var expected: u32 = 0;
    while (it.next()) |v| : (expected += 1) try testing.expectEqual(expected, v.*);
    try testing.expectEqual(@as(u32, 5), expected);
    log.reset(null);
    try testing.expect(log.items.len >= 5);
    try testing.expectEqual(@as(u32, 0), log.count.load(.monotonic));
}

test "a spilled entry starts blank, and a slot grown for the next frame starts blank too" {
    var log = try FrameLog(u32).init(1, 7);
    defer log.deinit(null);
    log.claim().?.* = 1;
    try testing.expectEqual(@as(u32, 7), log.claim().?.*);
    log.reset(null);
    _ = log.claim();
    try testing.expectEqual(@as(u32, 7), log.claim().?.*);
}
