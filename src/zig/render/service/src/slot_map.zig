const std = @import("std");
const rc = @import("render_service.zig");
const c = rc.c;

const handles = @import("handle").Handles(c);
const GENERATION_FIRST: u32 = 1;

pub fn SlotMap(comptime T: type) type {
    return struct {
        const Self = @This();

        const Slot = struct {
            payload: T,
            generation: u32,
            occupied: bool,
        };

        slots: std.ArrayListUnmanaged(Slot),
        free: std.ArrayListUnmanaged(u32),
        alloc: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{ .slots = .empty, .free = .empty, .alloc = alloc };
        }

        pub fn deinit(self: *Self) void {
            self.slots.deinit(self.alloc);
            self.free.deinit(self.alloc);
        }

        pub fn insert(self: *Self, value: T) u32 {
            if (self.free.pop()) |idx| {
                const s = &self.slots.items[idx];
                s.payload = value;
                s.occupied = true;
                return handles.make(idx, s.generation);
            }
            const idx: u32 = @intCast(self.slots.items.len);
            if (idx > handles.index_mask) return c.KE_HANDLE_NONE;
            self.slots.append(self.alloc, .{ .payload = value, .generation = GENERATION_FIRST, .occupied = true }) catch return c.KE_HANDLE_NONE;
            return handles.make(idx, GENERATION_FIRST);
        }

        pub fn get(self: *Self, bits: u32) ?*T {
            if (bits == c.KE_HANDLE_NONE) return null;
            const idx = handles.index(bits);
            if (idx >= self.slots.items.len) return null;
            const s = &self.slots.items[idx];
            if (!s.occupied or s.generation != handles.generation(bits)) return null;
            return &s.payload;
        }

        pub fn remove(self: *Self, bits: u32) ?T {
            const idx = handles.index(bits);
            if (bits == c.KE_HANDLE_NONE or idx >= self.slots.items.len) return null;
            const s = &self.slots.items[idx];
            if (!s.occupied or s.generation != handles.generation(bits)) return null;
            const payload = s.payload;
            s.occupied = false;
            s.generation = (s.generation +% 1) & handles.generation_mask;
            if (s.generation == 0) s.generation = GENERATION_FIRST;
            self.free.append(self.alloc, idx) catch {};
            return payload;
        }

        pub fn forEach(self: *Self, ctx: anytype, comptime f: fn (@TypeOf(ctx), *T) void) void {
            for (self.slots.items) |*s| {
                if (s.occupied) f(ctx, &s.payload);
            }
        }
    };
}

const testing = std.testing;

test "a removed slot's handle no longer resolves" {
    var map = SlotMap(u32).init(testing.allocator);
    defer map.deinit();

    const h = map.insert(7);
    try testing.expectEqual(@as(u32, 7), map.get(h).?.*);
    try testing.expectEqual(@as(?u32, 7), map.remove(h));
    try testing.expect(map.get(h) == null);
}

test "a reused slot answers to a new generation only" {
    var map = SlotMap(u32).init(testing.allocator);
    defer map.deinit();

    const first = map.insert(1);
    _ = map.remove(first);
    const second = map.insert(2);

    try testing.expectEqual(handles.index(first), handles.index(second));
    try testing.expect(handles.generation(first) != handles.generation(second));
    try testing.expect(map.get(first) == null);
    try testing.expectEqual(@as(u32, 2), map.get(second).?.*);
}

test "the generation wraps past zero so no live handle equals the none handle" {
    var map = SlotMap(u32).init(testing.allocator);
    defer map.deinit();

    var h = map.insert(0);
    var turns: u32 = 0;
    while (turns <= handles.generation_mask) : (turns += 1) {
        _ = map.remove(h);
        h = map.insert(0);
        try testing.expect(h != c.KE_HANDLE_NONE);
        try testing.expect(handles.generation(h) != 0);
    }
}

test "the none handle never resolves" {
    var map = SlotMap(u32).init(testing.allocator);
    defer map.deinit();

    _ = map.insert(1);
    try testing.expect(map.get(c.KE_HANDLE_NONE) == null);
    try testing.expect(map.remove(c.KE_HANDLE_NONE) == null);
}
