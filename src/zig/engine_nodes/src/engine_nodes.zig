//! Registers the engine's node types, the catalogue `ke_engine_node_types` describes, through a `ke_node_types`.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_engine_nodes").logFn };

const abi_engine_node_types = @import("abi_engine_node_types");
const abi_framework = @import("abi_framework");
const abi_part = @import("abi_part");
const abi_result = @import("abi_result");
const heap = @import("heap");
const part = @import("part");

const R = @import("result").Result(.{});
const log = std.log.scoped(.engine_nodes);

var owner_ref: u8 = 0;

/// The owner's destroy: releases nothing, the types stay with the node types they were registered in.
fn release(_: ?*anyopaque) callconv(.c) void {}

/// The factory: registers every type of the catalogue through `types`, stopping at the first it refuses.
export fn ke_engine_nodes_create(types_in: ?*abi_framework.c.ke_node_types, out_owner: ?*abi_part.c.ke_owner) callconv(.c) abi_result.c.ke_result {
    const out = out_owner orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_part.c.ke_owner);
    const types = types_in orelse return R.code(error.InvalidArgument);
    for (&abi_engine_node_types.c.ke_engine_node_types) |*desc| {
        var cid: abi_framework.c.ke_component_id = 0;
        const made = types.register_type.?(types, @ptrCast(desc), &cid);
        if (made != R.ok) {
            log.warn("registering the engine node type {s} failed", .{std.mem.span(desc.name.?)});
            return made;
        }
    }
    out.* = .{ .ref = &owner_ref, .destroy = release };
    return R.ok;
}

const parts = [_]abi_part.c.ke_part{
    part.of(ke_engine_nodes_create, .{ .name = "engine_nodes", .slots = &.{"types"}, .set_log = @ptrCast(&@import("log").Destination("ke_engine_nodes").setLogCallback) }),
};

/// The library's parts.
export fn ke_engine_nodes_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

const testing = std.testing;
const zsub = @import("zsub");

test "the part registers every engine node type through the node types it is bound to and provides nothing" {
    var types: zsub.For(abi_framework.c.ke_node_types) = undefined;
    try types.init();
    defer types.deinit();
    _ = types.when(.register_type).writesFresh(2);
    var count: usize = 0;
    const p = ke_engine_nodes_parts(&count).?;
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqual(@as(usize, 0), p.provides_count);
    const bound_types = [_]?*anyopaque{types.api()};
    const bound = [_]abi_part.c.ke_part_bound{.{ .instances = @ptrCast(&bound_types), .count = 1 }};
    var owner: abi_part.c.ke_owner = undefined;
    try R.check(p.create.?(p, &bound[0], null, &owner));
    try types.received(.register_type).times(abi_engine_node_types.c.KE_ENGINE_NODE_TYPE_COUNT);
    owner.destroy.?(owner.ref);
}

test "a type the node types refuse stops the registration and leaves the owner zeroed" {
    var types: zsub.For(abi_framework.c.ke_node_types) = undefined;
    try types.init();
    defer types.deinit();
    _ = types.when(.register_type).returns(R.code(error.InvalidArgument));
    var owner: abi_part.c.ke_owner = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_engine_nodes_create(types.api(), &owner));
    try types.received(.register_type).times(1);
    try testing.expect(owner.ref == null);
}

test "the engine nodes leak nothing" {
    try heap.expectNoLeaks();
}
