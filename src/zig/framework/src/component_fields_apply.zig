
const std = @import("std");

const c = @import("c.zig").c;

fn asFloat(v: *const c.ke_variant) ?f32 {
    return switch (v.type) {
        c.KE_VARIANT_FLOAT => @floatCast(v.unnamed_0.f),
        c.KE_VARIANT_INT => @floatFromInt(v.unnamed_0.i),
        else => null,
    };
}

fn asInt(v: *const c.ke_variant) ?i64 {
    return switch (v.type) {
        c.KE_VARIANT_INT => v.unnamed_0.i,
        c.KE_VARIANT_BOOL => @intFromBool(v.unnamed_0.b),
        c.KE_VARIANT_FLOAT => @intFromFloat(v.unnamed_0.f),
        else => null,
    };
}

fn asBool(v: *const c.ke_variant) ?bool {
    return switch (v.type) {
        c.KE_VARIANT_BOOL => v.unnamed_0.b,
        c.KE_VARIANT_INT => v.unnamed_0.i != 0,
        else => null,
    };
}

/// A vec4 out of anything narrower, filling w with 1: a color authored as three
/// components means opaque, which is the only reading that leaves the field
/// usable rather than fully transparent.
fn asVec4(v: *const c.ke_variant) ?c.ke_vec4 {
    return switch (v.type) {
        c.KE_VARIANT_VEC4 => v.unnamed_0.v4,
        c.KE_VARIANT_QUAT => .{ .x = v.unnamed_0.q.x, .y = v.unnamed_0.q.y, .z = v.unnamed_0.q.z, .w = v.unnamed_0.q.w },
        c.KE_VARIANT_VEC3 => .{ .x = v.unnamed_0.v3.x, .y = v.unnamed_0.v3.y, .z = v.unnamed_0.v3.z, .w = 1 },
        else => null,
    };
}

/// A vec3 out of anything narrower, filling z with 0. A field where 0 is the
/// wrong fill (a scale, where it collapses the object) is the domain callback's
/// to correct afterwards.
fn asVec3(v: *const c.ke_variant) ?c.ke_vec3 {
    return switch (v.type) {
        c.KE_VARIANT_VEC3 => v.unnamed_0.v3,
        c.KE_VARIANT_VEC4 => .{ .x = v.unnamed_0.v4.x, .y = v.unnamed_0.v4.y, .z = v.unnamed_0.v4.z },
        c.KE_VARIANT_VEC2 => .{ .x = v.unnamed_0.v2.x, .y = v.unnamed_0.v2.y, .z = 0 },
        else => null,
    };
}

fn asVec2(v: *const c.ke_variant) ?c.ke_vec2 {
    return switch (v.type) {
        c.KE_VARIANT_VEC2 => v.unnamed_0.v2,
        c.KE_VARIANT_VEC3 => .{ .x = v.unnamed_0.v3.x, .y = v.unnamed_0.v3.y },
        c.KE_VARIANT_VEC4 => .{ .x = v.unnamed_0.v4.x, .y = v.unnamed_0.v4.y },
        else => null,
    };
}

/// Writes `value` at `base + offset`. The field's own size decides the integer
/// width written, so the table describes a uint8_t flag and a uint32_t enum
/// through one path.
fn writeInt(base: [*]u8, field: *const c.ke_component_field, value: i64) void {
    const p = base + field.offset;
    switch (field.size) {
        1 => p[0] = @truncate(@as(u64, @bitCast(value))),
        2 => std.mem.writeInt(u16, p[0..2], @truncate(@as(u64, @bitCast(value))), .little),
        4 => std.mem.writeInt(u32, p[0..4], @truncate(@as(u64, @bitCast(value))), .little),
        8 => std.mem.writeInt(u64, p[0..8], @bitCast(value), .little),
        else => {},
    }
}

fn writeBytes(base: [*]u8, field: *const c.ke_component_field, bytes: []const u8) void {
    if (bytes.len != field.size) return;
    @memcpy((base + field.offset)[0..bytes.len], bytes);
}

fn writeField(base: [*]u8, field: *const c.ke_component_field, v: *const c.ke_variant) void {
    switch (field.type) {
        c.KE_VARIANT_FLOAT => {
            const f = asFloat(v) orelse return;
            if (field.size == 4) writeBytes(base, field, std.mem.asBytes(&f));
            if (field.size == 8) {
                const d: f64 = f;
                writeBytes(base, field, std.mem.asBytes(&d));
            }
        },
        c.KE_VARIANT_INT => writeInt(base, field, asInt(v) orelse return),
        c.KE_VARIANT_BOOL => writeInt(base, field, @intFromBool(asBool(v) orelse return)),
        c.KE_VARIANT_VEC2 => {
            const val = asVec2(v) orelse return;
            writeBytes(base, field, std.mem.asBytes(&val));
        },
        c.KE_VARIANT_VEC3 => {
            const val = asVec3(v) orelse return;
            writeBytes(base, field, std.mem.asBytes(&val));
        },
        c.KE_VARIANT_VEC4, c.KE_VARIANT_QUAT => {
            const val = asVec4(v) orelse return;
            writeBytes(base, field, std.mem.asBytes(&val));
        },
        c.KE_VARIANT_STRING => {
            if (v.type != c.KE_VARIANT_STRING) return;
            const s = v.unnamed_0.s orelse return;
            const src = std.mem.span(s);
            const dst = (base + field.offset)[0..field.size];
            const n = @min(src.len, dst.len - 1);
            @memcpy(dst[0..n], src[0..n]);
            dst[n] = 0;
        },
        else => {},
    }
}

fn keyIs(key: [*c]const u8, name: [*c]const u8) bool {
    if (key == null or name == null) return false;
    return std.mem.eql(u8, std.mem.span(key), std.mem.span(name));
}

/// Applies every entry the table describes. Entries are scanned per field
/// rather than the reverse so a duplicated key resolves the same way a
/// hand-written apply resolved it: the last one authored wins.
pub fn apply(
    component: ?*anyopaque,
    entries: [*c]c.ke_variant_table_entry,
    count: u32,
    fields: [*]const c.ke_component_field,
    field_count: u32,
) void {
    const base: [*]u8 = @ptrCast(component orelse return);
    if (entries == null or count == 0) return;

    for (entries[0..count]) |*entry| {
        for (fields[0..field_count]) |*field| {
            if (!keyIs(entry.key, field.name)) continue;
            writeField(base, field, &entry.value);
            entry.consumed = true;
            break;
        }
    }
}

/// Writes every field's declared default into a component that has none yet.
///
/// A component a scene creates has no node behind it to run a constructor, so
/// without this a block that authors one field leaves every other at zero — a
/// roughness of 0 where the header says 1. Seeding through the same writeField
/// the authored path uses means a default and a value can never disagree about
/// what the field's type accepts.
pub fn seedDefaults(
    component: ?*anyopaque,
    fields: [*]const c.ke_component_field,
    field_count: u32,
) void {
    const base: [*]u8 = @ptrCast(component orelse return);
    for (fields[0..field_count]) |*field| {
        if (field.default_value.type == c.KE_VARIANT_NULL) continue;
        writeField(base, field, &field.default_value);
    }
}

const testing = std.testing;

const Probe = extern struct {
    flag: u8,
    count: i32,
    amount: f32,
    tint: c.ke_vec4,
    where: c.ke_vec3,
    label: [8]u8,
};

const probe_fields = [_]c.ke_component_field{
    .{ .name = "flag", .type = c.KE_VARIANT_BOOL, .offset = @offsetOf(Probe, "flag"), .size = 1 },
    .{ .name = "count", .type = c.KE_VARIANT_INT, .offset = @offsetOf(Probe, "count"), .size = 4 },
    .{ .name = "amount", .type = c.KE_VARIANT_FLOAT, .offset = @offsetOf(Probe, "amount"), .size = 4 },
    .{ .name = "tint", .type = c.KE_VARIANT_VEC4, .offset = @offsetOf(Probe, "tint"), .size = 16 },
    .{ .name = "where", .type = c.KE_VARIANT_VEC3, .offset = @offsetOf(Probe, "where"), .size = 12 },
    .{ .name = "label", .type = c.KE_VARIANT_STRING, .offset = @offsetOf(Probe, "label"), .size = 8 },
};

/// Copies into a mutable buffer because apply marks each entry it takes, and a
/// test's literal list is const.
fn applyTo(p: *Probe, list: []const c.ke_variant_table_entry) void {
    var buf: [8]c.ke_variant_table_entry = undefined;
    @memcpy(buf[0..list.len], list);
    apply(p, &buf, @intCast(list.len), &probe_fields, probe_fields.len);
}

fn vFloat(f: f64) c.ke_variant {
    return .{ .type = c.KE_VARIANT_FLOAT, .unnamed_0 = .{ .f = f } };
}

fn vInt(i: i64) c.ke_variant {
    return .{ .type = c.KE_VARIANT_INT, .unnamed_0 = .{ .i = i } };
}

const seeded_fields = [_]c.ke_component_field{
    .{ .name = "amount", .type = c.KE_VARIANT_FLOAT, .offset = @offsetOf(Probe, "amount"), .size = 4, .default_value = vFloat(1.0) },
    .{ .name = "tint", .type = c.KE_VARIANT_VEC4, .offset = @offsetOf(Probe, "tint"), .size = 16, .default_value = .{ .type = c.KE_VARIANT_VEC4, .unnamed_0 = .{ .v4 = .{ .x = 1, .y = 1, .z = 1, .w = 1 } } } },
    .{ .name = "count", .type = c.KE_VARIANT_INT, .offset = @offsetOf(Probe, "count"), .size = 4 },
};

test "a field the header gives a default starts there, not at zero" {
    var p = std.mem.zeroes(Probe);
    seedDefaults(&p, &seeded_fields, seeded_fields.len);

    try testing.expectEqual(@as(f32, 1.0), p.amount);
    try testing.expectEqual(@as(f32, 1.0), p.tint.w);
    try testing.expectEqual(@as(i32, 0), p.count);
}

test "an authored value overrides the default it was seeded with" {
    var p = std.mem.zeroes(Probe);
    seedDefaults(&p, &seeded_fields, seeded_fields.len);
    var one = [_]c.ke_variant_table_entry{
        .{ .key = "amount", .value = vFloat(0.25) },
    };
    apply(&p, &one, one.len, &seeded_fields, seeded_fields.len);

    try testing.expectEqual(@as(f32, 0.25), p.amount);
    try testing.expectEqual(@as(f32, 1.0), p.tint.w);
}

test "writes each described field at its own offset" {
    var p = std.mem.zeroes(Probe);
    applyTo(&p, &.{
        .{ .key = "flag", .value = .{ .type = c.KE_VARIANT_BOOL, .unnamed_0 = .{ .b = true } } },
        .{ .key = "count", .value = vInt(7) },
        .{ .key = "amount", .value = vFloat(2.5) },
    });
    try testing.expectEqual(@as(u8, 1), p.flag);
    try testing.expectEqual(@as(i32, 7), p.count);
    try testing.expectEqual(@as(f32, 2.5), p.amount);
}

test "an integer authored for a float field is coerced, and the reverse" {
    var p = std.mem.zeroes(Probe);
    applyTo(&p, &.{
        .{ .key = "amount", .value = vInt(3) },
        .{ .key = "count", .value = vFloat(9.0) },
    });
    try testing.expectEqual(@as(f32, 3.0), p.amount);
    try testing.expectEqual(@as(i32, 9), p.count);
}

test "a color authored with three components is opaque, not transparent" {
    var p = std.mem.zeroes(Probe);
    applyTo(&p, &.{
        .{ .key = "tint", .value = .{ .type = c.KE_VARIANT_VEC3, .unnamed_0 = .{ .v3 = .{ .x = 1, .y = 0.5, .z = 0.25 } } } },
    });
    try testing.expectEqual(@as(f32, 1), p.tint.w);
}

test "a vec2 widens into a vec3 field, leaving z at zero for the domain to correct" {
    var p = std.mem.zeroes(Probe);
    applyTo(&p, &.{
        .{ .key = "where", .value = .{ .type = c.KE_VARIANT_VEC2, .unnamed_0 = .{ .v2 = .{ .x = 4, .y = 5 } } } },
    });
    try testing.expectEqual(@as(f32, 4), p.where.x);
    try testing.expectEqual(@as(f32, 0), p.where.z);
}

test "a string longer than the field still leaves it NUL-terminated" {
    var p = std.mem.zeroes(Probe);
    applyTo(&p, &.{
        .{ .key = "label", .value = .{ .type = c.KE_VARIANT_STRING, .unnamed_0 = .{ .s = "abcdefghijkl" } } },
    });
    try testing.expectEqual(@as(u8, 0), p.label[7]);
    try testing.expectEqualStrings("abcdefg", std.mem.sliceTo(&p.label, 0));
}

test "a key the table does not describe leaves the component untouched" {
    var p = std.mem.zeroes(Probe);
    applyTo(&p, &.{
        .{ .key = "nonesuch", .value = vFloat(1) },
    });
    try testing.expectEqual(std.mem.zeroes(Probe), p);
}

test "a value whose type cannot be coerced is skipped, not written as garbage" {
    var p = std.mem.zeroes(Probe);
    p.amount = 1.5;
    applyTo(&p, &.{
        .{ .key = "amount", .value = .{ .type = c.KE_VARIANT_STRING, .unnamed_0 = .{ .s = "nope" } } },
    });
    try testing.expectEqual(@as(f32, 1.5), p.amount);
}

test "the last value authored for a duplicated key wins" {
    var p = std.mem.zeroes(Probe);
    applyTo(&p, &.{
        .{ .key = "count", .value = vInt(1) },
        .{ .key = "count", .value = vInt(2) },
    });
    try testing.expectEqual(@as(i32, 2), p.count);
}
