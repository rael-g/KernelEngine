//! The `ke_scene_component_set` a plugin hands out for its scene components, built from a list the
//! plugin declares, so every plugin registers them the same way and reports the same failures.

const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_result = @import("abi_result");

/// One component of a set: the name it is registered under, its size and alignment, its field table, and the
/// apply callback the world consults after the table, if the plugin has one.
pub const Entry = struct {
    name: [*:0]const u8,
    size: usize,
    alignment: usize,
    fields: []const abi_ecs.ke_component_field = &.{},
    apply: abi_framework.ke_component_apply_fn = null,
};

/// The set for `entries`. It holds no state, so every handle the factory returns shares one
/// vtable and destroying a handle releases nothing.
pub fn Set(comptime entries: []const Entry) type {
    return struct {
        var api: abi_framework.ke_scene_component_set = .{ .handle = null, .register_into = registerInto };

        /// Slot `register_into`. Registers the entries in order and stops at the first one the
        /// ecs or the world refuses, failing with its code.
        fn registerInto(self: [*c]abi_framework.ke_scene_component_set, ecs_in: [*c]abi_ecs.ke_ecs, world_in: [*c]abi_framework.ke_world) callconv(.c) abi_result.ke_result {
            if (self == null or ecs_in == null or world_in == null) return abi_result.KE_RESULT_INVALID_ARGUMENT;
            const ecs = ecs_in;
            const world = world_in;
            inline for (entries) |e| {
                const fields: [*c]const abi_ecs.ke_component_field = if (e.fields.len == 0) null else e.fields.ptr;
                var cid: abi_ecs.ke_component_id = abi_ecs.KE_COMPONENT_INVALID;
                const made = ecs.*.component_register.?(ecs, &abi_ecs.ke_component_params{ .name = e.name, .size = e.size, .alignment = e.alignment, .fields = fields, .field_count = @intCast(e.fields.len) }, &cid);
                if (made != abi_result.KE_OK) return made;
                if (e.fields.len > 0) {
                    const described = world.*.register_component_fields.?(world, cid, fields, @intCast(e.fields.len));
                    if (described != abi_result.KE_OK) return described;
                }
                if (e.apply != null) {
                    const applied = world.*.register_component_apply.?(world, cid, e.apply, null);
                    if (applied != abi_result.KE_OK) return applied;
                }
            }
            return abi_result.KE_OK;
        }

        fn destroy(_: [*c]abi_framework.ke_scene_component_set) callconv(.c) void {}

        /// The handle a plugin's factory returns.
        pub fn handle() abi_framework.ke_scene_component_set_handle {
            return .{ .ref = &api, .destroy = destroy };
        }
    };
}
