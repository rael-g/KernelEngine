
const std = @import("std");

const c = @import("c.zig").c;
const fields_rt = @import("component_fields").Fields(c);

fn writeField(base: [*]u8, field: *const c.ke_component_field, v: *const c.ke_variant) bool {
    return fields_rt.write(base, field, v);
}

fn keyIs(key: [*c]const u8, name: [*c]const u8) bool {
    if (key == null or name == null) return false;
    return std.mem.eql(u8, std.mem.span(key), std.mem.span(name));
}

/// Applies every entry the table describes; a duplicated key resolves to the
/// last one authored. Returns the first field that could not hold the value
/// authored for it, or null when every entry was applied.
pub fn apply(
    component: ?*anyopaque,
    entries: [*c]c.ke_variant_table_entry,
    count: u32,
    fields: [*]const c.ke_component_field,
    field_count: u32,
) ?*const c.ke_component_field {
    const base: [*]u8 = @ptrCast(component orelse return null);
    if (entries == null or count == 0) return null;

    for (entries[0..count]) |*entry| {
        for (fields[0..field_count]) |*field| {
            if (!keyIs(entry.key, field.name)) continue;
            entry.consumed = true;
            if (!writeField(base, field, &entry.value)) return field;
            break;
        }
    }
    return null;
}

/// Writes every field's declared default into a component.
pub fn seedDefaults(
    component: ?*anyopaque,
    fields: [*]const c.ke_component_field,
    field_count: u32,
) void {
    fields_rt.seedDefaults(component, fields, field_count);
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

fn applyRefused(p: *Probe, list: []const c.ke_variant_table_entry) ?*const c.ke_component_field {
    var buf: [8]c.ke_variant_table_entry = undefined;
    @memcpy(buf[0..list.len], list);
    return apply(p, &buf, @intCast(list.len), &probe_fields, probe_fields.len);
}

fn applyTo(p: *Probe, list: []const c.ke_variant_table_entry) void {
    _ = applyRefused(p, list);
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
    _ = apply(&p, &one, one.len, &seeded_fields, seeded_fields.len);

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

test "a float that is not a number authored for an integer field writes zero" {
    var p = std.mem.zeroes(Probe);
    p.count = 7;
    applyTo(&p, &.{
        .{ .key = "count", .value = vFloat(std.math.nan(f64)) },
    });
    try testing.expectEqual(@as(i32, 0), p.count);
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

test "a value whose type cannot be coerced is refused by name, not written as garbage" {
    var p = std.mem.zeroes(Probe);
    p.amount = 1.5;
    const refused = applyRefused(&p, &.{
        .{ .key = "amount", .value = .{ .type = c.KE_VARIANT_STRING, .unnamed_0 = .{ .s = "nope" } } },
    });
    try testing.expectEqual(@as(f32, 1.5), p.amount);
    try testing.expect(refused != null);
    try testing.expectEqualStrings("amount", std.mem.span(refused.?.name));
}

test "the last value authored for a duplicated key wins" {
    var p = std.mem.zeroes(Probe);
    applyTo(&p, &.{
        .{ .key = "count", .value = vInt(1) },
        .{ .key = "count", .value = vInt(2) },
    });
    try testing.expectEqual(@as(i32, 2), p.count);
}
