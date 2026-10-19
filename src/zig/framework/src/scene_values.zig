//! Turns the tables of a scene file into engine variants, in memory owned by an arena that lives as
//! long as the loader reading them.

const std = @import("std");

const c = @import("c");
const heap = @import("heap");

/// Owns the strings and variant tables read from scene files. Nothing frees an allocation on its
/// own; `deinit` releases all of them together, so a pointer handed out stays valid until the
/// loader that owns this arena is destroyed.
pub const Arena = struct {
    inner: std.heap.ArenaAllocator,

    pub fn init() Arena {
        return .{ .inner = .init(heap.gpa) };
    }

    pub fn allocArray(self: *Arena, comptime T: type, n: usize) ?[]T {
        if (n == 0) return &.{};
        return self.inner.allocator().alloc(T, n) catch null;
    }

    /// The copy lives until the arena is deinitialized, so the caller may free its source at once.
    pub fn dupeZ(self: *Arena, src: [*c]const u8) ?[*:0]u8 {
        if (src == null) return null;
        const owned = self.inner.allocator().dupeZ(u8, std.mem.span(src)) catch return null;
        return owned.ptr;
    }

    pub fn deinit(self: *Arena) void {
        self.inner.deinit();
    }
};

pub fn variantNull() c.ke_variant {
    return .{ .type = c.KE_VARIANT_NULL, .unnamed_0 = .{ .i = 0 } };
}
fn variantBool(b: bool) c.ke_variant {
    return .{ .type = c.KE_VARIANT_BOOL, .unnamed_0 = .{ .b = b } };
}
fn variantInt(i: i64) c.ke_variant {
    return .{ .type = c.KE_VARIANT_INT, .unnamed_0 = .{ .i = i } };
}
fn variantFloat(f: f64) c.ke_variant {
    return .{ .type = c.KE_VARIANT_FLOAT, .unnamed_0 = .{ .f = f } };
}
fn variantString(s: ?[*:0]const u8) c.ke_variant {
    return .{ .type = c.KE_VARIANT_STRING, .unnamed_0 = .{ .s = s } };
}
fn variantVec2(x: f32, y: f32) c.ke_variant {
    return .{ .type = c.KE_VARIANT_VEC2, .unnamed_0 = .{ .v2 = .{ .x = x, .y = y } } };
}
fn variantVec3(x: f32, y: f32, z: f32) c.ke_variant {
    return .{ .type = c.KE_VARIANT_VEC3, .unnamed_0 = .{ .v3 = .{ .x = x, .y = y, .z = z } } };
}
fn variantVec4(x: f32, y: f32, z: f32, w: f32) c.ke_variant {
    return .{ .type = c.KE_VARIANT_VEC4, .unnamed_0 = .{ .v4 = .{ .x = x, .y = y, .z = z, .w = w } } };
}
fn variantTable(t: *const c.ke_variant_table) c.ke_variant {
    return .{ .type = c.KE_VARIANT_TABLE, .unnamed_0 = .{ .t = t } };
}

/// A one-element or empty array becomes null. A longer one becomes a vector variant sized by its
/// length, up to the widest vector, so elements beyond that are dropped. An element that is not a
/// number stays zero, and nothing reports it.
fn variantFromArray(arr: *c.toml_array_t) c.ke_variant {
    const n = c.toml_array_nelem(arr);
    var comps = [_]f32{ 0, 0, 0, 0 };
    const len = @min(n, @as(c_int, comps.len));
    var k: c_int = 0;
    while (k < len) : (k += 1) {
        const d = c.toml_double_at(arr, k);
        if (d.ok != 0) {
            comps[@intCast(k)] = @floatCast(d.u.d);
            continue;
        }
        const i = c.toml_int_at(arr, k);
        if (i.ok != 0) comps[@intCast(k)] = @floatFromInt(i.u.i);
    }
    if (n == 2) return variantVec2(comps[0], comps[1]);
    if (n == 3) return variantVec3(comps[0], comps[1], comps[2]);
    if (n >= 4) return variantVec4(comps[0], comps[1], comps[2], comps[3]);
    return variantNull();
}

fn variantFromTable(arena: *Arena, tbl: *c.toml_table_t) c.ke_variant {
    const n: usize = @intCast(c.toml_table_nkval(tbl) + c.toml_table_ntab(tbl) + c.toml_table_narr(tbl));
    const entries = arena.allocArray(c.ke_variant_table_entry, n) orelse return variantNull();
    const vtbl_mem = arena.allocArray(c.ke_variant_table, 1) orelse return variantNull();

    var count: usize = 0;
    var k: c_int = 0;
    while (count < n) : (k += 1) {
        const key = c.toml_key_in(tbl, k) orelse break;
        entries[count] = .{
            .key = arena.dupeZ(key),
            .value = readVarIn(arena, tbl, key),
        };
        count += 1;
    }

    vtbl_mem[0] = .{ .count = @intCast(count), .entries = entries.ptr };
    return variantTable(&vtbl_mem[0]);
}

/// Reads the value of `key` in `tbl` by trying the TOML kinds in turn: string, integer, float,
/// boolean, array, table. A string is copied into the arena and its TOML buffer freed here. A value
/// of any other kind, such as a date, reads as null, and nothing reports it.
pub fn readVarIn(arena: *Arena, tbl: *c.toml_table_t, key: [*c]const u8) c.ke_variant {
    const ds = c.toml_string_in(tbl, key);
    if (ds.ok != 0) {
        const v = variantString(arena.dupeZ(ds.u.s));
        std.c.free(ds.u.s);
        return v;
    }
    const di = c.toml_int_in(tbl, key);
    if (di.ok != 0) return variantInt(di.u.i);
    const dd = c.toml_double_in(tbl, key);
    if (dd.ok != 0) return variantFloat(dd.u.d);
    const db = c.toml_bool_in(tbl, key);
    if (db.ok != 0) return variantBool(db.u.b != 0);
    if (c.toml_array_in(tbl, key)) |arr| return variantFromArray(arr);
    if (c.toml_table_in(tbl, key)) |sub| return variantFromTable(arena, sub);
    return variantNull();
}

pub fn tableEntryCount(tbl: *c.toml_table_t) usize {
    return @intCast(c.toml_table_nkval(tbl) + c.toml_table_narr(tbl) + c.toml_table_ntab(tbl));
}

/// Reads every entry of a component table into arena memory and returns them, or null when the
/// table has no entries or the arena cannot hold them. The caller treats both as an unreadable
/// block.
pub fn buildEntries(arena: *Arena, tbl: *c.toml_table_t) ?[]c.ke_variant_table_entry {
    const n = tableEntryCount(tbl);
    if (n == 0) return null;
    const entries = arena.allocArray(c.ke_variant_table_entry, n) orelse return null;
    var count: usize = 0;
    var k: c_int = 0;
    while (count < n) : (k += 1) {
        const key = c.toml_key_in(tbl, k) orelse break;
        entries[count] = .{
            .key = arena.dupeZ(key),
            .value = readVarIn(arena, tbl, key),
        };
        count += 1;
    }
    return entries[0..count];
}
