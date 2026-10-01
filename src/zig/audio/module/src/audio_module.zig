const c = @import("cimport.zig").c;

fn registerFields(w: *c.ke_world, cid: c.ke_component_id, table: anytype) void {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    _ = w.register_component_fields.?(w, cid, table, @intCast(fields.len), null);
}

fn registerComponent(
    e: *c.ke_ecs,
    name: [*c]const u8,
    comptime T: type,
    table: anytype,
) c.ke_component_id {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    return e.component_register.?(e, name, @sizeOf(T), table, @intCast(fields.len), null);
}

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
