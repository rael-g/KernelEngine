//! The generic path from authored table entries to component memory, driven by a component's field
//! table and written through the ecs.

const abi_ecs_variant = @import("abi_ecs_variant");
const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_result = @import("abi_result");

fn writeField(ecs: *abi_ecs.c.ke_ecs, component: *anyopaque, field: *const abi_ecs.c.ke_component_field, v: *const abi_ecs_variant.c.ke_variant) bool {
    return ecs.component_field_write.?(ecs, component, field, v) == abi_result.c.KE_OK;
}

/// Turns a string written for a field with enum names into the integer it stands for. Returns
/// false for a name the field does not declare; any other value passes unchanged.
fn namedValue(field: *const abi_ecs.c.ke_component_field, value: *abi_ecs_variant.c.ke_variant) bool {
    if (field.enum_names == null or value.type != abi_ecs_variant.c.KE_VARIANT_STRING) return true;
    const names: [*]const ?[*:0]const u8 = @ptrCast(field.enum_names);
    for (names[0..field.enum_count], 0..) |name, index| {
        if (!keyIs(value.unnamed_0.s, name)) continue;
        value.* = .{ .type = abi_ecs_variant.c.KE_VARIANT_INT, .unnamed_0 = .{ .i = @intCast(index) } };
        return true;
    }
    return false;
}

fn keyIs(key: [*c]const u8, name: [*c]const u8) bool {
    if (key == null or name == null) return false;
    return std.mem.eql(u8, std.mem.span(key), std.mem.span(name));
}

/// Writes each entry whose key names a field, marks it consumed so that a caller can find the keys
/// nothing understood, and returns null; or returns the field whose value the ecs refused. It
/// stops at that value: the entries before it stay written, and the entries after it are not marked
/// consumed. A key given twice is written twice, so the later value is what the field holds.
pub fn apply(
    ecs: *abi_ecs.c.ke_ecs,
    component: ?*anyopaque,
    entries: [*c]abi_ecs_variant.c.ke_variant_table_entry,
    count: u32,
    fields: [*]const abi_ecs.c.ke_component_field,
    field_count: u32,
) ?*const abi_ecs.c.ke_component_field {
    const base = component orelse return null;
    if (entries == null or count == 0) return null;

    for (entries[0..count]) |*entry| {
        for (fields[0..field_count]) |*field| {
            if (!keyIs(entry.key, field.name)) continue;
            entry.consumed = true;
            var value = entry.value;
            if (!namedValue(field, &value)) return field;
            if (!writeField(ecs, base, field, &value)) return field;
            break;
        }
    }
    return null;
}

/// Seeds the declared default of each field that has one. It reports no failure: a default the ecs
/// refuses is not returned to the caller.
pub fn seedDefaults(
    ecs: *abi_ecs.c.ke_ecs,
    component: ?*anyopaque,
    fields: [*]const abi_ecs.c.ke_component_field,
    field_count: u32,
) void {
    const base = component orelse return;
    for (fields[0..field_count]) |*field| {
        if (field.default_value.type == abi_ecs_variant.c.KE_VARIANT_NULL) continue;
        _ = writeField(ecs, base, field, &field.default_value);
    }
}

const testing = std.testing;

const FakeEcs = struct {
    api: abi_ecs.c.ke_ecs,
    refused: ?[*:0]const u8 = null,
    written: [8]struct { field: [*:0]const u8, value: i64 } = undefined,
    count: usize = 0,

    fn init(self: *FakeEcs) void {
        self.* = .{ .api = std.mem.zeroes(abi_ecs.c.ke_ecs) };
        self.api.handle = self;
        self.api.component_field_write = &componentFieldWrite;
    }

    fn componentFieldWrite(self: ?*abi_ecs.c.ke_ecs, _: ?*anyopaque, field: ?*const abi_ecs.c.ke_component_field, value: ?*const abi_ecs_variant.c.ke_variant) callconv(.c) abi_result.c.ke_result {
        const e: *FakeEcs = @ptrCast(@alignCast(self.?.handle));
        const name = field.?.name.?;
        if (e.refused) |r| if (std.mem.orderZ(u8, r, name) == .eq) return abi_result.c.KE_RESULT_INVALID_ARGUMENT;
        e.written[e.count] = .{ .field = name, .value = value.?.unnamed_0.i };
        e.count += 1;
        return abi_result.c.KE_OK;
    }
};

fn vInt(i: i64) abi_ecs_variant.c.ke_variant {
    return .{ .type = abi_ecs_variant.c.KE_VARIANT_INT, .unnamed_0 = .{ .i = i } };
}

const table = [_]abi_ecs.c.ke_component_field{
    .{ .name = "count", .type = abi_ecs_variant.c.KE_VARIANT_INT, .offset = 0, .size = 4, .default_value = vInt(5) },
    .{ .name = "amount", .type = abi_ecs_variant.c.KE_VARIANT_INT, .offset = 4, .size = 4 },
};

var storage: [8]u8 = undefined;

test "each entry whose key names a field is written through the ecs and marked consumed" {
    var ecs: FakeEcs = undefined;
    ecs.init();
    var entries = [_]abi_ecs_variant.c.ke_variant_table_entry{
        .{ .key = "amount", .value = vInt(2) },
        .{ .key = "nonesuch", .value = vInt(1) },
    };
    try testing.expectEqual(@as(?*const abi_ecs.c.ke_component_field, null), apply(&ecs.api, &storage, &entries, entries.len, &table, table.len));
    try testing.expectEqual(@as(usize, 1), ecs.count);
    try testing.expectEqualStrings("amount", std.mem.span(ecs.written[0].field));
    try testing.expect(entries[0].consumed);
    try testing.expect(!entries[1].consumed);
}

test "a value the ecs refuses is returned by its field, and the entries after it are left alone" {
    var ecs: FakeEcs = undefined;
    ecs.init();
    ecs.refused = "count";
    var entries = [_]abi_ecs_variant.c.ke_variant_table_entry{
        .{ .key = "count", .value = vInt(1) },
        .{ .key = "amount", .value = vInt(2) },
    };
    const refusing = apply(&ecs.api, &storage, &entries, entries.len, &table, table.len);
    try testing.expectEqualStrings("count", std.mem.span(refusing.?.name.?));
    try testing.expectEqual(@as(usize, 0), ecs.count);
    try testing.expect(!entries[1].consumed);
}

test "a key given twice is written twice, the later value last" {
    var ecs: FakeEcs = undefined;
    ecs.init();
    var entries = [_]abi_ecs_variant.c.ke_variant_table_entry{
        .{ .key = "count", .value = vInt(1) },
        .{ .key = "count", .value = vInt(2) },
    };
    _ = apply(&ecs.api, &storage, &entries, entries.len, &table, table.len);
    try testing.expectEqual(@as(usize, 2), ecs.count);
    try testing.expectEqual(@as(i64, 2), ecs.written[1].value);
}

test "only the fields that declare a default are seeded" {
    var ecs: FakeEcs = undefined;
    ecs.init();
    seedDefaults(&ecs.api, &storage, &table, table.len);
    try testing.expectEqual(@as(usize, 1), ecs.count);
    try testing.expectEqualStrings("count", std.mem.span(ecs.written[0].field));
    try testing.expectEqual(@as(i64, 5), ecs.written[0].value);
}

test "a name a field declares is written as its index, and an unknown one is refused" {
    var fake: FakeEcs = undefined;
    fake.init();
    var slot: u32 = 0;
    const names = [_]?[*:0]const u8{ "Left", "Right" };
    const fields = [_]abi_ecs.c.ke_component_field{.{ .name = "action", .type = abi_ecs_variant.c.KE_VARIANT_INT, .enum_names = @ptrCast(&names), .enum_count = names.len }};
    var entries = [_]abi_ecs_variant.c.ke_variant_table_entry{.{ .key = "action", .value = .{ .type = abi_ecs_variant.c.KE_VARIANT_STRING, .unnamed_0 = .{ .s = "Right" } } }};
    try testing.expect(apply(&fake.api, &slot, &entries, 1, &fields, 1) == null);
    try testing.expectEqual(@as(i64, 1), fake.written[0].value);
    entries[0].value.unnamed_0.s = "Up";
    try testing.expect(apply(&fake.api, &slot, &entries, 1, &fields, 1) != null);
}
