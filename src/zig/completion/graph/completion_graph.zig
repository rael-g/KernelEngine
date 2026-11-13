//! Work that starts once the completions it depends on finished, shared by the job and async
//! systems: the counting of dependencies, the hand-off of results, the drain of work that waits on
//! completions of another origin and the release of finished work.

const std = @import("std");
const abi_completion = @import("abi_completion");
const abi_result = @import("abi_result");

pub const Completion = abi_completion.c.ke_completion;
pub const Result = abi_result.c.ke_result;

const closed: usize = 1;

/// The graph of one system. `B` is the backend: it has a `Payload` type held by every node, and
/// the functions `start(*B, *Node)`, called once a node's dependencies all finished, on a thread
/// the backend accepts; `wait(*B, *Node) Result`, which blocks the way the backend allows;
/// `canFree(*B, *Node) bool`, true once the backend no longer touches a finished node; and
/// `deinitPayload(*B, *Node)`.
pub fn Graph(comptime B: type) type {
    return struct {
        const Self = @This();

        /// One dependency of a node: where its result goes, and the completion of another origin
        /// still to be polled, null once satisfied or when the dependency is a node of this graph.
        pub const Link = struct {
            node: *Node,
            index: u32,
            next: ?*Link,
            foreign: ?*Completion,
        };

        /// A piece of work and the completion that reports it. `pending` counts the unfinished
        /// dependencies plus one held while the node is being linked; the thread that brings it to
        /// zero starts the node. `dependents` is the stack of links waiting on this node, swapped
        /// to `closed` when it finishes, after which `result` is final.
        pub const Node = struct {
            api: Completion,
            graph: *Self,
            finished: std.atomic.Value(bool),
            result: Result,
            pending: std.atomic.Value(u32),
            dependents: std.atomic.Value(usize),
            links: []Link,
            dep_results: []Result,
            next_waiting: ?*Node,
            next_retired: ?*Node,
            payload: B.Payload,
        };

        backend: *B,
        gpa: std.mem.Allocator,
        waiting: std.atomic.Value(?*Node),
        retired: std.atomic.Value(?*Node),

        pub fn init(backend: *B, gpa: std.mem.Allocator) Self {
            return .{ .backend = backend, .gpa = gpa, .waiting = .init(null), .retired = .init(null) };
        }

        /// Allocates a node over `deps`, which every caller has checked to hold no null, without
        /// linking it: `link` makes it wait on them.
        pub fn alloc(self: *Self, deps: []const ?*Completion, payload: B.Payload) error{OutOfMemory}!*Node {
            const node = try self.gpa.create(Node);
            errdefer self.gpa.destroy(node);
            const links = try self.gpa.alloc(Link, deps.len);
            errdefer self.gpa.free(links);
            const dep_results = try self.gpa.alloc(Result, deps.len);
            node.* = .{
                .api = .{ .handle = node, .poll = poll, .wait = wait, .release = release },
                .graph = self,
                .finished = .init(false),
                .result = abi_result.c.KE_OK,
                .pending = .init(@intCast(deps.len + 1)),
                .dependents = .init(0),
                .links = links,
                .dep_results = dep_results,
                .next_waiting = null,
                .next_retired = null,
                .payload = payload,
            };
            for (links, deps, 0..) |*l, d, i| {
                l.* = .{ .node = node, .index = @intCast(i), .next = null, .foreign = d };
                dep_results[i] = abi_result.c.KE_OK;
            }
            return node;
        }

        /// Makes `node` wait on its dependencies and starts it once none is left; it may start
        /// before this returns.
        pub fn link(self: *Self, node: *Node) void {
            var satisfied: u32 = 0;
            var has_foreign = false;
            for (node.links) |*l| {
                const dep = l.foreign.?;
                if (self.own(dep)) |dep_node| {
                    l.foreign = null;
                    if (!pushDependent(dep_node, l)) {
                        node.dep_results[l.index] = dep_node.result;
                        satisfied += 1;
                    }
                } else {
                    var r: Result = abi_result.c.KE_OK;
                    if (dep.poll.?(dep, &r)) {
                        node.dep_results[l.index] = r;
                        l.foreign = null;
                        satisfied += 1;
                    } else has_foreign = true;
                }
            }
            if (has_foreign) pushStack(&self.waiting, node, .waiting);
            self.settle(node, satisfied + 1);
        }

        fn settle(self: *Self, node: *Node, count: u32) void {
            if (count == 0) return;
            if (node.pending.fetchSub(count, .acq_rel) == count) self.backend.start(node);
        }

        /// Records what the node finished with, hands it to every node waiting on it, and marks
        /// the node finished; the node must not be touched by the caller afterwards.
        pub fn finish(self: *Self, node: *Node, result: Result) void {
            node.result = result;
            var top = node.dependents.swap(closed, .acq_rel);
            while (top != 0) {
                const l: *Link = @ptrFromInt(top);
                top = if (l.next) |n| @intFromPtr(n) else 0;
                l.node.dep_results[l.index] = result;
                self.settle(l.node, 1);
            }
            node.finished.store(true, .release);
        }

        /// Polls the dependencies of other origins of every waiting node, starting the nodes left
        /// with none, and frees the released nodes the backend no longer touches.
        pub fn drain(self: *Self) void {
            var top = self.waiting.swap(null, .acq_rel);
            while (top) |node| {
                top = node.next_waiting;
                var satisfied: u32 = 0;
                var left = false;
                for (node.links) |*l| {
                    const dep = l.foreign orelse continue;
                    var r: Result = abi_result.c.KE_OK;
                    if (dep.poll.?(dep, &r)) {
                        node.dep_results[l.index] = r;
                        l.foreign = null;
                        satisfied += 1;
                    } else left = true;
                }
                if (left) pushStack(&self.waiting, node, .waiting);
                self.settle(node, satisfied);
            }
            self.freeRetired();
        }

        fn freeRetired(self: *Self) void {
            var top = self.retired.swap(null, .acq_rel);
            while (top) |node| {
                top = node.next_retired;
                if (node.finished.load(.acquire) and self.backend.canFree(node)) destroy(node) else pushStack(&self.retired, node, .retired);
            }
        }

        /// Frees every released node; called once the backend runs nothing any more.
        pub fn deinit(self: *Self) void {
            var top = self.retired.swap(null, .acq_rel);
            while (top) |node| {
                top = node.next_retired;
                destroy(node);
            }
        }

        /// Frees a node that was never linked.
        pub fn discard(_: *Self, node: *Node) void {
            destroy(node);
        }

        /// The node behind `c` when it belongs to this graph.
        pub fn own(self: *Self, c: *Completion) ?*Node {
            if (c.poll != poll) return null;
            const node: *Node = @ptrCast(@alignCast(c.handle));
            return if (node.graph == self) node else null;
        }

        pub fn nodeOf(c: *Completion) *Node {
            return @ptrCast(@alignCast(c.handle));
        }

        fn destroy(node: *Node) void {
            const gpa = node.graph.gpa;
            node.graph.backend.deinitPayload(node);
            gpa.free(node.links);
            gpa.free(node.dep_results);
            gpa.destroy(node);
        }

        fn pushDependent(dep: *Node, l: *Link) bool {
            var top = dep.dependents.load(.acquire);
            while (true) {
                if (top == closed) return false;
                l.next = if (top == 0) null else @ptrFromInt(top);
                top = dep.dependents.cmpxchgWeak(top, @intFromPtr(l), .acq_rel, .acquire) orelse return true;
            }
        }

        fn pushStack(head: *std.atomic.Value(?*Node), node: *Node, comptime which: enum { waiting, retired }) void {
            const field = if (which == .waiting) "next_waiting" else "next_retired";
            var top = head.load(.acquire);
            while (true) {
                @field(node, field) = top;
                top = head.cmpxchgWeak(top, node, .acq_rel, .acquire) orelse return;
            }
        }

        /// Slot `poll` of every node's completion.
        fn poll(c_in: ?*Completion, out_result: ?*Result) callconv(.c) bool {
            const node = nodeOf(c_in orelse return false);
            if (!node.finished.load(.acquire)) return false;
            if (out_result) |out| out.* = node.result;
            return true;
        }

        /// Slot `wait` of every node's completion; the backend decides how the thread waits.
        fn wait(c_in: ?*Completion) callconv(.c) Result {
            const node = nodeOf(c_in orelse return abi_result.c.KE_RESULT_INVALID_ARGUMENT);
            return node.graph.backend.wait(node);
        }

        /// Slot `release` of every node's completion. A node the backend still touches, or that
        /// has not finished, waits among the retired until a drain frees it.
        fn release(c_in: ?*Completion) callconv(.c) void {
            const node = nodeOf(c_in orelse return);
            const self = node.graph;
            if (node.finished.load(.acquire) and self.backend.canFree(node)) destroy(node) else pushStack(&self.retired, node, .retired);
        }
    };
}

/// A bounded queue many threads push to and one thread pops from, without a lock.
pub fn Ring(comptime T: type) type {
    return struct {
        const Self = @This();
        const Slot = struct { seq: std.atomic.Value(usize), value: T };

        gpa: std.mem.Allocator,
        slots: []Slot,
        capacity: u32,
        held: std.atomic.Value(u32),
        enqueue: std.atomic.Value(usize),
        dequeue: usize,

        pub fn init(gpa: std.mem.Allocator, capacity: u32) error{OutOfMemory}!Self {
            const size = std.math.ceilPowerOfTwo(usize, @max(capacity, 2)) catch return error.OutOfMemory;
            const slots = try gpa.alloc(Slot, size);
            for (slots, 0..) |*s, i| s.seq = .init(i);
            return .{ .gpa = gpa, .slots = slots, .capacity = capacity, .held = .init(0), .enqueue = .init(0), .dequeue = 0 };
        }

        pub fn deinit(self: *Self) void {
            self.gpa.free(self.slots);
        }

        /// False when the queue holds `capacity` values.
        pub fn push(self: *Self, value: T) bool {
            if (self.held.fetchAdd(1, .acq_rel) >= self.capacity) {
                _ = self.held.fetchSub(1, .acq_rel);
                return false;
            }
            const mask = self.slots.len - 1;
            var pos = self.enqueue.load(.monotonic);
            while (true) {
                const slot = &self.slots[pos & mask];
                const seq = slot.seq.load(.acquire);
                const dif = @as(isize, @bitCast(seq)) -% @as(isize, @bitCast(pos));
                if (dif == 0) {
                    pos = self.enqueue.cmpxchgWeak(pos, pos + 1, .monotonic, .monotonic) orelse {
                        slot.value = value;
                        slot.seq.store(pos + 1, .release);
                        return true;
                    };
                } else if (dif < 0) {
                    return false;
                } else pos = self.enqueue.load(.monotonic);
            }
        }

        /// Called by the one consuming thread.
        pub fn pop(self: *Self) ?T {
            const slot = &self.slots[self.dequeue & (self.slots.len - 1)];
            if (slot.seq.load(.acquire) != self.dequeue + 1) return null;
            const value = slot.value;
            slot.seq.store(self.dequeue + self.slots.len, .release);
            self.dequeue += 1;
            _ = self.held.fetchSub(1, .acq_rel);
            return value;
        }
    };
}
