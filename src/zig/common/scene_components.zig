//! The `ke_scene_component_set` a plugin hands out for its scene components, built from a list the
//! plugin declares, so every plugin registers them the same way and reports the same failures.

/// One component of a set: the name it is registered under, its size, its field table, and the
/// apply callback the world consults after the table, if the plugin has one.
pub fn Entry(comptime c: type) type {
    return struct {
        name: [*:0]const u8,
        size: usize,
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
        /// ecs or the world refuses, whose error it reports.
        fn registerInto(self: [*c]c.ke_scene_component_set, ecs_in: [*c]c.ke_ecs, world_in: [*c]c.ke_world, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
            if (self == null or ecs_in == null or world_in == null) {
                c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "scene component set: a null argument", @src().file, @intCast(@src().line), null);
                return false;
            }
            const ecs = ecs_in;
            const world = world_in;
            inline for (entries) |e| {
                const fields: [*c]const c.ke_component_field = if (e.fields.len == 0) null else e.fields.ptr;
                const cid = ecs.*.component_register.?(ecs, e.name, e.size, fields, @intCast(e.fields.len), out_error);
                if (cid == c.KE_COMPONENT_INVALID) return false;
                if (e.fields.len > 0 and !world.*.register_component_fields.?(world, cid, fields, @intCast(e.fields.len), out_error)) return false;
                if (e.apply != null and !world.*.register_component_apply.?(world, cid, e.apply, null, out_error)) return false;
            }
            return true;
        }

        fn destroy(_: [*c]c.ke_scene_component_set) callconv(.c) void {}

        /// The handle a plugin's factory returns.
        pub fn handle() c.ke_scene_component_set_handle {
            return .{ .ref = &api, .destroy = destroy };
        }
    };
}
