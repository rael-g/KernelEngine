//! Exports `ke_audio_register_scene_apply`, which makes the audio player component known to an ECS
//! and to a world.

const c = @import("cimport.zig").c;

/// Hands the world a component id and the field table that describes that component, with the
/// table's length taken from its type. The result of the registration is discarded.
fn registerFields(w: *c.ke_world, cid: c.ke_component_id, table: anytype) void {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    _ = w.register_component_fields.?(w, cid, table, @intCast(fields.len), null);
}

/// Declares a component to the ECS under a name, with the size of its type and its field table,
/// and returns the id the ECS assigns. The table's length is taken from its type.
fn registerComponent(
    e: *c.ke_ecs,
    name: [*c]const u8,
    comptime T: type,
    table: anytype,
) c.ke_component_id {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    return e.component_register.?(e, name, @sizeOf(T), table, @intCast(fields.len), null);
}

/// Registers the audio player component with the ECS and then its fields with the world. Returns
/// false, registering nothing, when the ecs pointer or the world pointer is null. Otherwise it
/// always returns true: the component id from the ECS and the result of the world registration
/// are not checked.
export fn ke_audio_register_scene_apply(ecs: ?*c.ke_ecs, world: ?*c.ke_world) callconv(.c) bool {
    const e = ecs orelse return false;
    const w = world orelse return false;

    const player_cid = registerComponent(
        e,
        c.KE_COMPONENT_NAME_AUDIO_PLAYER,
        c.ke_audio_player_component,
        &c.ke_audio_player_component_fields,
    );
    registerFields(w, player_cid, &c.ke_audio_player_component_fields);
    return true;
}
