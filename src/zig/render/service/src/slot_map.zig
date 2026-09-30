const std = @import("std");
const rc = @import("render_service.zig");
const c = rc.c;

const INDEX_BITS = 20;
const GENERATION_BITS = 12;
const INDEX_MASK: u32 = (1 << INDEX_BITS) - 1;
const GENERATION_MASK: u32 = (1 << GENERATION_BITS) - 1;
const GENERATION_FIRST: u32 = 1;

pub fn packHandle(index: u32, generation: u32) u32 {
    return (index & INDEX_MASK) | ((generation & GENERATION_MASK) << INDEX_BITS);
}
pub fn handleIndex(bits: u32) u32 {
    return bits & INDEX_MASK;
}
pub fn handleGeneration(bits: u32) u32 {
    return (bits >> INDEX_BITS) & GENERATION_MASK;
}

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
                return packHandle(idx, s.generation);
            }
            const idx: u32 = @intCast(self.slots.items.len);
            if (idx > INDEX_MASK) return c.KE_HANDLE_NONE;
            self.slots.append(self.alloc, .{ .payload = value, .generation = GENERATION_FIRST, .occupied = true }) catch return c.KE_HANDLE_NONE;
            return packHandle(idx, GENERATION_FIRST);
        }

        pub fn get(self: *Self, bits: u32) ?*T {
            if (bits == c.KE_HANDLE_NONE) return null;
            const idx = handleIndex(bits);
            if (idx >= self.slots.items.len) return null;
            const s = &self.slots.items[idx];
            if (!s.occupied or s.generation != handleGeneration(bits)) return null;
            return &s.payload;
        }

        pub fn remove(self: *Self, bits: u32) ?T {
            const idx = handleIndex(bits);
            if (bits == c.KE_HANDLE_NONE or idx >= self.slots.items.len) return null;
            const s = &self.slots.items[idx];
            if (!s.occupied or s.generation != handleGeneration(bits)) return null;
            const payload = s.payload;
            s.occupied = false;
            s.generation = (s.generation +% 1) & GENERATION_MASK;
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
