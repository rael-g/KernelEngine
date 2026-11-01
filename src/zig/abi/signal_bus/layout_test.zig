const std = @import("std");
const abi = @import("abi");
const c = @import("c");

fn expectSameLayout(comptime A: type, comptime C: type) !void {
    @setEvalBranchQuota(100_000_000);
    if (@typeInfo(C) == .@"opaque") return;
    try std.testing.expectEqual(@sizeOf(C), @sizeOf(A));
    try std.testing.expectEqual(@alignOf(C), @alignOf(A));
    switch (@typeInfo(A)) {
        .@"struct" => |s| inline for (s.fields) |f| {
            try std.testing.expectEqual(@offsetOf(C, f.name), @offsetOf(A, f.name));
            try expectSameLayout(f.type, @FieldType(C, f.name));
        },
        .@"union" => |u| inline for (u.fields) |f| try expectSameLayout(f.type, @FieldType(C, f.name)),
        else => {},
    }
}

fn translated(comptime name: []const u8) type {
    return if (@hasDecl(c, name)) @field(c, name) else @field(c, "struct_" ++ name);
}

test "every record is laid out as the header lays it out" {
    @setEvalBranchQuota(100_000_000);
    try expectSameLayout(abi.c.ke_signal_delivery, translated("ke_signal_delivery"));
    try expectSameLayout(abi.c.ke_signal_bus, translated("ke_signal_bus"));
    try expectSameLayout(abi.c.ke_signal_bus_handle, translated("ke_signal_bus_handle"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_SIGNAL_PAYLOAD_SIZE_UNKNOWN), @as(i128, abi.c.KE_SIGNAL_PAYLOAD_SIZE_UNKNOWN));
}

extern const layout_values: [21]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_signal_delivery),
        @offsetOf(abi.c.ke_signal_delivery, "source"),
        @offsetOf(abi.c.ke_signal_delivery, "target"),
        @offsetOf(abi.c.ke_signal_delivery, "signal_id"),
        @offsetOf(abi.c.ke_signal_delivery, "handler_id"),
        @offsetOf(abi.c.ke_signal_delivery, "payload"),
        @offsetOf(abi.c.ke_signal_delivery, "payload_size"),
        @sizeOf(abi.c.ke_signal_bus),
        @offsetOf(abi.c.ke_signal_bus, "handle"),
        @offsetOf(abi.c.ke_signal_bus, "signal_id"),
        @offsetOf(abi.c.ke_signal_bus, "signal_lookup"),
        @offsetOf(abi.c.ke_signal_bus, "connect"),
        @offsetOf(abi.c.ke_signal_bus, "disconnect"),
        @offsetOf(abi.c.ke_signal_bus, "forget_entity"),
        @offsetOf(abi.c.ke_signal_bus, "emit"),
        @offsetOf(abi.c.ke_signal_bus, "deliveries"),
        @offsetOf(abi.c.ke_signal_bus, "clear_frame"),
        @sizeOf(abi.c.ke_signal_bus_handle),
        @offsetOf(abi.c.ke_signal_bus_handle, "ref"),
        @offsetOf(abi.c.ke_signal_bus_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
