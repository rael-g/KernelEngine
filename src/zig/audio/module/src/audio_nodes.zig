//! Registers audio's node types, the catalogue `ke_audio_node_types` describes, through a `ke_node_types`.

const std = @import("std");
const abi_framework = @import("abi_framework");
const abi_part = @import("abi_part");
const abi_result = @import("abi_result");
const abi_audio_node_types = @import("abi_audio_node_types");
const node_catalogue = @import("node_catalogue");

const R = @import("result").Result(.{});

/// The factory: registers every type of the catalogue through `types`, stopping at the first it refuses.
pub export fn ke_audio_nodes_create(types: ?*abi_framework.c.ke_node_types, out_owner: ?*abi_part.c.ke_owner) callconv(.c) abi_result.c.ke_result {
    return node_catalogue.register(types, &abi_audio_node_types.c.ke_audio_node_types, out_owner);
}

const zsub = @import("zsub");

test "every audio's node type is registered through the node types it is given" {
    var types: zsub.For(abi_framework.c.ke_node_types) = undefined;
    try types.init();
    defer types.deinit();
    _ = types.when(.register_type).writesFresh(2);
    var owner: abi_part.c.ke_owner = undefined;
    try R.check(ke_audio_nodes_create(types.api(), &owner));
    try types.received(.register_type).times(abi_audio_node_types.c.KE_AUDIO_NODE_TYPE_COUNT);
    owner.destroy.?(owner.ref);
}
