//! Registers a domain's node types, a catalogue its contract header describes, through a `ke_node_types`: the body
//! every domain's node types factory shares.

const std = @import("std");
const abi_framework = @import("abi_framework");
const abi_part = @import("abi_part");
const abi_result = @import("abi_result");

const R = @import("result").Result(.{});
const log = std.log.scoped(.node_catalogue);

var owner_ref: u8 = 0;

/// The owner's destroy: releases nothing, the types stay with the node types they were registered in.
fn release(_: ?*anyopaque) callconv(.c) void {}

/// Registers every type of `catalogue` through `types_in`, stopping at the first it refuses, and writes an owner
/// that releases nothing to `out_owner`, left zeroed on failure.
pub fn register(types_in: ?*abi_framework.c.ke_node_types, catalogue: anytype, out_owner: ?*abi_part.c.ke_owner) abi_result.c.ke_result {
    const out = out_owner orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_part.c.ke_owner);
    const types = types_in orelse return R.code(error.InvalidArgument);
    for (catalogue) |*desc| {
        var cid: abi_framework.c.ke_component_id = 0;
        const made = types.register_type.?(types, @ptrCast(desc), &cid);
        if (made != R.ok) {
            log.warn("registering the node type {s} failed", .{std.mem.span(@as([*:0]const u8, desc.name.?))});
            return made;
        }
    }
    out.* = .{ .ref = &owner_ref, .destroy = release };
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");

const two_types = [_]abi_framework.c.ke_node_type_desc{ .{ .name = "first" }, .{ .name = "second" } };

test "every type of the catalogue is registered through the node types and the owner releases nothing" {
    var types: zsub.For(abi_framework.c.ke_node_types) = undefined;
    try types.init();
    defer types.deinit();
    _ = types.when(.register_type).writesFresh(2);
    var owner: abi_part.c.ke_owner = undefined;
    try R.check(register(types.api(), &two_types, &owner));
    try types.received(.register_type).times(two_types.len);
    owner.destroy.?(owner.ref);
}

test "a type the node types refuse stops the registration and leaves the owner zeroed" {
    var types: zsub.For(abi_framework.c.ke_node_types) = undefined;
    try types.init();
    defer types.deinit();
    _ = types.when(.register_type).returns(R.code(error.InvalidArgument));
    var owner: abi_part.c.ke_owner = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), register(types.api(), &two_types, &owner));
    try types.received(.register_type).times(1);
    try testing.expect(owner.ref == null);
}

test "a null node types is refused" {
    var owner: abi_part.c.ke_owner = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), register(null, &two_types, &owner));
}
