//! Converts a variant to the type of a component field and writes it at the field's place, and
//! seeds a component's field defaults the same way. It holds no state and allocates nothing.

const std = @import("std");
const abi_ecs = @import("abi_ecs");
const abi_math = @import("abi_math");

/// Accepts a float or an integer; any other variant has no float reading.
fn asFloat(v: *const abi_ecs.ke_variant) ?f32 {
    return switch (v.type) {
        abi_ecs.KE_VARIANT_FLOAT => @floatCast(v.unnamed_0.f),
        abi_ecs.KE_VARIANT_INT => @floatFromInt(v.unnamed_0.i),
        else => null,
    };
}

/// Accepts an integer, a float, which saturates, or a boolean; any other variant has no
/// integer reading.
fn asInt(v: *const abi_ecs.ke_variant) ?i64 {
    return switch (v.type) {
        abi_ecs.KE_VARIANT_INT => v.unnamed_0.i,
        abi_ecs.KE_VARIANT_FLOAT => std.math.lossyCast(i64, v.unnamed_0.f),
        abi_ecs.KE_VARIANT_BOOL => @intFromBool(v.unnamed_0.b),
        else => null,
    };
}

/// Accepts a boolean, or an integer, which is true when not zero, and yields 1 or 0 for
/// the integer store.
fn asBool(v: *const abi_ecs.ke_variant) ?i64 {
    return switch (v.type) {
        abi_ecs.KE_VARIANT_BOOL => @intFromBool(v.unnamed_0.b),
        abi_ecs.KE_VARIANT_INT => @intFromBool(v.unnamed_0.i != 0),
        else => null,
    };
}

/// Accepts a four-component vector, a quaternion, or a three-component vector, which gains
/// a last component of one.
fn asVec4(v: *const abi_ecs.ke_variant) ?abi_math.ke_vec4 {
    return switch (v.type) {
        abi_ecs.KE_VARIANT_VEC4 => v.unnamed_0.v4,
        abi_ecs.KE_VARIANT_QUAT => .{ .x = v.unnamed_0.q.x, .y = v.unnamed_0.q.y, .z = v.unnamed_0.q.z, .w = v.unnamed_0.q.w },
        abi_ecs.KE_VARIANT_VEC3 => .{ .x = v.unnamed_0.v3.x, .y = v.unnamed_0.v3.y, .z = v.unnamed_0.v3.z, .w = 1.0 },
        else => null,
    };
}

/// Accepts a three-component vector, a four-component one, which drops its last component,
/// or a two-component one, which gains a last component of zero.
fn asVec3(v: *const abi_ecs.ke_variant) ?abi_math.ke_vec3 {
    return switch (v.type) {
        abi_ecs.KE_VARIANT_VEC3 => v.unnamed_0.v3,
        abi_ecs.KE_VARIANT_VEC4 => .{ .x = v.unnamed_0.v4.x, .y = v.unnamed_0.v4.y, .z = v.unnamed_0.v4.z },
        abi_ecs.KE_VARIANT_VEC2 => .{ .x = v.unnamed_0.v2.x, .y = v.unnamed_0.v2.y, .z = 0.0 },
        else => null,
    };
}

/// Accepts a two-component vector, or a wider one, which drops its extra components.
fn asVec2(v: *const abi_ecs.ke_variant) ?abi_math.ke_vec2 {
    return switch (v.type) {
        abi_ecs.KE_VARIANT_VEC2 => v.unnamed_0.v2,
        abi_ecs.KE_VARIANT_VEC3 => .{ .x = v.unnamed_0.v3.x, .y = v.unnamed_0.v3.y },
        abi_ecs.KE_VARIANT_VEC4 => .{ .x = v.unnamed_0.v4.x, .y = v.unnamed_0.v4.y },
        else => null,
    };
}

/// Copies the bytes to the field's offset only when their count is the field's size.
fn writeBytes(base: [*]u8, field: *const abi_ecs.ke_component_field, src: []const u8) bool {
    if (src.len != field.size) return false;
    @memcpy(base[field.offset..][0..src.len], src);
    return true;
}

fn writeValue(base: [*]u8, field: *const abi_ecs.ke_component_field, value: anytype) bool {
    return writeBytes(base, field, std.mem.asBytes(&value));
}

/// Stores the low bytes of the integer when the field's size is one of the integer widths
/// of one, two, four or eight bytes, and refuses any other size.
fn writeInt(base: [*]u8, field: *const abi_ecs.ke_component_field, value: i64) bool {
    return switch (field.size) {
        1 => writeBytes(base, field, std.mem.asBytes(&@as(u8, @truncate(@as(u64, @bitCast(value)))))),
        2 => writeBytes(base, field, std.mem.asBytes(&@as(u16, @truncate(@as(u64, @bitCast(value)))))),
        4 => writeBytes(base, field, std.mem.asBytes(&@as(u32, @truncate(@as(u64, @bitCast(value)))))),
        8 => writeBytes(base, field, std.mem.asBytes(&@as(u64, @bitCast(value)))),
        else => false,
    };
}

/// Stores the value into the place the field describes inside the component, converted to
/// the field's declared type. Returns false, and stores nothing, when the component, the
/// field or the value pointer is null, when the value's variant type does not convert to
/// the declared type, or when the field's size does not fit that type.
pub fn write(component: ?*anyopaque, field: ?*const abi_ecs.ke_component_field, value: ?*const abi_ecs.ke_variant) bool {
    const base: [*]u8 = @ptrCast(component orelse return false);
    const f = field orelse return false;
    const v = value orelse return false;

    switch (f.type) {
        abi_ecs.KE_VARIANT_FLOAT => {
            const x = asFloat(v) orelse return false;
            if (f.size == 4) return writeValue(base, f, x);
            if (f.size == 8) return writeValue(base, f, @as(f64, x));
            return false;
        },
        abi_ecs.KE_VARIANT_INT => {
            const x = asInt(v) orelse return false;
            return writeInt(base, f, x);
        },
        abi_ecs.KE_VARIANT_BOOL => {
            const x = asBool(v) orelse return false;
            return writeInt(base, f, x);
        },
        abi_ecs.KE_VARIANT_VEC2 => {
            const x = asVec2(v) orelse return false;
            return writeValue(base, f, x);
        },
        abi_ecs.KE_VARIANT_VEC3 => {
            const x = asVec3(v) orelse return false;
            return writeValue(base, f, x);
        },
        abi_ecs.KE_VARIANT_VEC4, abi_ecs.KE_VARIANT_QUAT => {
            const x = asVec4(v) orelse return false;
            return writeValue(base, f, x);
        },
        abi_ecs.KE_VARIANT_STRING => {
            if (v.type != abi_ecs.KE_VARIANT_STRING or v.unnamed_0.s == null or f.size == 0) return false;
            const src = std.mem.span(v.unnamed_0.s.?);
            const n = @min(src.len, @as(usize, f.size) - 1);
            @memcpy(base[f.offset..][0..n], src[0..n]);
            base[f.offset + n] = 0;
            return true;
        },
        else => return false,
    }
}

/// Stores the default of each field among the first entries of the table, as many as the
/// count gives, through `write`. Defaults of the null variant are skipped. A default that
/// `write` refuses is passed over with no report, and its field keeps the bytes it held.
pub fn seedDefaults(component: ?*anyopaque, fields: ?[*]const abi_ecs.ke_component_field, field_count: u32) void {
    if (component == null) return;
    const table = fields orelse return;
    for (table[0..field_count]) |*f| {
        if (f.default_value.type == abi_ecs.KE_VARIANT_NULL) continue;
        _ = write(component, f, &f.default_value);
    }
}

const testing = std.testing;

const Probe = extern struct {
    flag: u8,
    count: i32,
    amount: f32,
    tint: abi_math.ke_vec4,
    where: abi_math.ke_vec3,
    label: [8]u8,
};

fn fieldOf(comptime name: [:0]const u8, kind: abi_ecs.ke_variant_type) abi_ecs.ke_component_field {
    return .{ .name = name, .type = kind, .offset = @offsetOf(Probe, name), .size = @sizeOf(@FieldType(Probe, name)) };
}

fn vFloat(f: f64) abi_ecs.ke_variant {
    return .{ .type = abi_ecs.KE_VARIANT_FLOAT, .unnamed_0 = .{ .f = f } };
}

fn vInt(i: i64) abi_ecs.ke_variant {
    return .{ .type = abi_ecs.KE_VARIANT_INT, .unnamed_0 = .{ .i = i } };
}

test "each field is written at its own offset" {
    var p = std.mem.zeroes(Probe);
    try testing.expect(write(&p, &fieldOf("flag", abi_ecs.KE_VARIANT_BOOL), &.{ .type = abi_ecs.KE_VARIANT_BOOL, .unnamed_0 = .{ .b = true } }));
    try testing.expect(write(&p, &fieldOf("count", abi_ecs.KE_VARIANT_INT), &vInt(7)));
    try testing.expect(write(&p, &fieldOf("amount", abi_ecs.KE_VARIANT_FLOAT), &vFloat(2.5)));
    try testing.expectEqual(@as(u8, 1), p.flag);
    try testing.expectEqual(@as(i32, 7), p.count);
    try testing.expectEqual(@as(f32, 2.5), p.amount);
}

test "an integer written to a float field is converted, and the reverse" {
    var p = std.mem.zeroes(Probe);
    try testing.expect(write(&p, &fieldOf("amount", abi_ecs.KE_VARIANT_FLOAT), &vInt(3)));
    try testing.expect(write(&p, &fieldOf("count", abi_ecs.KE_VARIANT_INT), &vFloat(9.0)));
    try testing.expectEqual(@as(f32, 3.0), p.amount);
    try testing.expectEqual(@as(i32, 9), p.count);
}

test "a float that is not a number written to an integer field writes zero" {
    var p = std.mem.zeroes(Probe);
    p.count = 7;
    try testing.expect(write(&p, &fieldOf("count", abi_ecs.KE_VARIANT_INT), &vFloat(std.math.nan(f64))));
    try testing.expectEqual(@as(i32, 0), p.count);
}

test "a color written with three components is opaque, not transparent" {
    var p = std.mem.zeroes(Probe);
    try testing.expect(write(&p, &fieldOf("tint", abi_ecs.KE_VARIANT_VEC4), &.{ .type = abi_ecs.KE_VARIANT_VEC3, .unnamed_0 = .{ .v3 = .{ .x = 1, .y = 0.5, .z = 0.25 } } }));
    try testing.expectEqual(@as(f32, 1), p.tint.w);
}

test "a vec2 widens into a vec3 field, leaving z at zero" {
    var p = std.mem.zeroes(Probe);
    try testing.expect(write(&p, &fieldOf("where", abi_ecs.KE_VARIANT_VEC3), &.{ .type = abi_ecs.KE_VARIANT_VEC2, .unnamed_0 = .{ .v2 = .{ .x = 4, .y = 5 } } }));
    try testing.expectEqual(@as(f32, 4), p.where.x);
    try testing.expectEqual(@as(f32, 0), p.where.z);
}

test "a string longer than the field still leaves it NUL-terminated" {
    var p = std.mem.zeroes(Probe);
    try testing.expect(write(&p, &fieldOf("label", abi_ecs.KE_VARIANT_STRING), &.{ .type = abi_ecs.KE_VARIANT_STRING, .unnamed_0 = .{ .s = "abcdefghijkl" } }));
    try testing.expectEqual(@as(u8, 0), p.label[7]);
    try testing.expectEqualStrings("abcdefg", std.mem.sliceTo(&p.label, 0));
}

test "a value whose type does not convert is refused and nothing is written" {
    var p = std.mem.zeroes(Probe);
    p.amount = 1.5;
    try testing.expect(!write(&p, &fieldOf("amount", abi_ecs.KE_VARIANT_FLOAT), &.{ .type = abi_ecs.KE_VARIANT_STRING, .unnamed_0 = .{ .s = "nope" } }));
    try testing.expectEqual(@as(f32, 1.5), p.amount);
}

test "a field with a default starts there, and one without keeps its bytes" {
    var p = std.mem.zeroes(Probe);
    var amount = fieldOf("amount", abi_ecs.KE_VARIANT_FLOAT);
    amount.default_value = vFloat(1.0);
    const table = [_]abi_ecs.ke_component_field{ amount, fieldOf("count", abi_ecs.KE_VARIANT_INT) };
    seedDefaults(&p, &table, table.len);
    try testing.expectEqual(@as(f32, 1.0), p.amount);
    try testing.expectEqual(@as(i32, 0), p.count);
}
