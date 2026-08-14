const c = @import("cimport.zig").c;

/// Registers a generated field table, taking its length from the array type so
/// the count can never drift from the table it describes.
fn registerFields(w: *c.ke_world, cid: c.ke_component_id, table: anytype) void {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    _ = w.register_component_fields.?(w, cid, table, @intCast(fields.len), null);
}

export fn ke_audio_register_scene_apply(ecs: ?*c.ke_ecs, world: ?*c.ke_world) callconv(.c) bool {
    const e = ecs orelse return false;
    const w = world orelse return false;

    const player_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_AUDIO_PLAYER,
        @sizeOf(c.ke_audio_player_component), null);
    registerFields(w, player_cid, &c.ke_audio_player_component_fields);
    return true;
}
