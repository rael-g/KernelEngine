//! The `ke_scene_component_set` a plugin hands out for its scene components, built from a list the
//! plugin declares, so every plugin registers them the same way and reports the same failures.

/// One component of a set: the name it is registered under, its size and alignment, its field table, and the
/// apply callback the world consults after the table, if the plugin has one.
pub fn Entry(comptime c: type) type {
    return struct {
        name: [*:0]const u8,
        size: usize,
        alignment: usize,
        fields: []const c.ke_component_field = &.{},
        apply: c.ke_component_apply_fn = null,
    };
}

/// The set for `entries`. It holds no state, so every handle the factory returns shares one
/// vtable and destroying a handle releases nothing.
pub fn Set(comptime c: type, comptime entries: []const Entry(c)) type {
    return struct {
        var api: c.ke_scene_component_set = .{ .handle = null, .register_into = registerInto };

        /// Slot `register_into`. Registers the entries in order and stops at the first one the
        /// ecs or the world refuses, failing with its code.
        fn registerInto(self: [*c]c.ke_scene_component_set, ecs_in: [*c]c.ke_ecs, world_in: [*c]c.ke_world) callconv(.c) c.ke_result {
            if (self == null or ecs_in == null or world_in == null) return c.KE_RESULT_INVALID_ARGUMENT;
            const ecs = ecs_in;
            const world = world_in;
            inline for (entries) |e| {
                const fields: [*c]const c.ke_component_field = if (e.fields.len == 0) null else e.fields.ptr;
                var cid: c.ke_component_id = c.KE_COMPONENT_INVALID;
                const made = ecs.*.component_register.?(ecs, &c.ke_component_params{ .name = e.name, .size = e.size, .alignment = e.alignment, .fields = fields, .field_count = @intCast(e.fields.len) }, &cid);
                if (made != c.KE_OK) return made;
                if (e.fields.len > 0) {
                    const described = world.*.register_component_fields.?(world, cid, fields, @intCast(e.fields.len));
                    if (described != c.KE_OK) return described;
                }
                if (e.apply != null) {
                    const applied = world.*.register_component_apply.?(world, cid, e.apply, null);
                    if (applied != c.KE_OK) return applied;
                }
            }
            return c.KE_OK;
        }

        fn destroy(_: [*c]c.ke_scene_component_set) callconv(.c) void {}

        /// The handle a plugin's factory returns.
        pub fn handle() c.ke_scene_component_set_handle {
            return .{ .ref = &api, .destroy = destroy };
        }
    };
}
