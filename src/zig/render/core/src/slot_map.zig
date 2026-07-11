const std = @import("std");
const rc = @import("render_core.zig");
const c = rc.c;

// Generational slot map: a dense, growable store of T where each live element
// is addressed by a 32-bit handle packing {slot index, generation}. Freeing a
// slot bumps its generation, so a handle held past its free stops resolving —
// use-after-free is reported (null), never aliased onto whatever took the slot.
//
// This is the storage the render core's meshes/textures/materials sit in. The
// handle layout (index/generation bit split, KE_HANDLE_NONE) is the C ABI in
// handles.h; this mirrors it so a handle minted here is the same u32 a game or
// another module holds.

const INDEX_BITS = 20; // KE_HANDLE_INDEX_BITS
const GENERATION_BITS = 12; // KE_HANDLE_GENERATION_BITS
const INDEX_MASK: u32 = (1 << INDEX_BITS) - 1;
const GENERATION_MASK: u32 = (1 << GENERATION_BITS) - 1;
const INDEX_NONE: u32 = INDEX_MASK; // reserved: spells "no handle"

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
            generation: u32, // current generation of this slot
            occupied: bool,
        };

        slots: std.ArrayListUnmanaged(Slot),
        free: std.ArrayListUnmanaged(u32), // indices of vacant slots, ready to reuse
        alloc: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{ .slots = .empty, .free = .empty, .alloc = alloc };
        }

        pub fn deinit(self: *Self) void {
            self.slots.deinit(self.alloc);
            self.free.deinit(self.alloc);
        }

        // Inserts `value` and returns its handle bits, or KE_HANDLE_NONE if the
        // index space is exhausted (INDEX_NONE slots) or allocation fails.
        pub fn insert(self: *Self, value: T) u32 {
            if (self.free.pop()) |idx| {
                const s = &self.slots.items[idx];
                s.payload = value;
                s.occupied = true;
                return packHandle(idx, s.generation);
            }
            const idx: u32 = @intCast(self.slots.items.len);
            if (idx >= INDEX_NONE) return c.KE_HANDLE_NONE; // index space full
            self.slots.append(self.alloc, .{ .payload = value, .generation = 0, .occupied = true }) catch return c.KE_HANDLE_NONE;
            return packHandle(idx, 0);
        }

        // Resolves a handle to a live payload pointer, or null if the handle is
        // KE_HANDLE_NONE, out of range, points at a vacant slot, or carries a
        // generation that no longer matches the slot (stale handle).
        pub fn get(self: *Self, bits: u32) ?*T {
            if (bits == c.KE_HANDLE_NONE) return null;
            const idx = handleIndex(bits);
            if (idx >= self.slots.items.len) return null;
            const s = &self.slots.items[idx];
            if (!s.occupied or s.generation != handleGeneration(bits)) return null;
            return &s.payload;
        }

        // Frees a handle's slot for reuse and bumps its generation. Returns the
        // freed payload (so the caller can destroy the GPU objects it owns), or
        // null if the handle did not resolve to a live slot. The generation
        // wraps within GENERATION_BITS; a handle that survives that many reuses
        // of the same slot can alias again — the accepted bound of the scheme.
        pub fn remove(self: *Self, bits: u32) ?T {
            const idx = handleIndex(bits);
            if (bits == c.KE_HANDLE_NONE or idx >= self.slots.items.len) return null;
            const s = &self.slots.items[idx];
            if (!s.occupied or s.generation != handleGeneration(bits)) return null;
            const payload = s.payload;
            s.occupied = false;
            s.generation = (s.generation +% 1) & GENERATION_MASK;
            self.free.append(self.alloc, idx) catch {}; // a lost free slot leaks a slot, not memory-unsafe
            return payload;
        }

        // Iterates every live payload once, in slot order. Used at teardown to
        // destroy whatever is still resident.
        pub fn forEach(self: *Self, ctx: anytype, comptime f: fn (@TypeOf(ctx), *T) void) void {
            for (self.slots.items) |*s| {
                if (s.occupied) f(ctx, &s.payload);
            }
        }
    };
}
