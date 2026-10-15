//! Exports `ke_audio_register_scene_apply`, which makes the audio player component known to an ECS
//! and to a world.

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @import("cimport.zig").c;

/// Hands the world a component id and the field table that describes that component, with the
/// table's length taken from its type, and returns whether the world took it.
fn registerFields(w: *c.ke_world, cid: c.ke_component_id, table: anytype) bool {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    return w.register_component_fields.?(w, cid, table, @intCast(fields.len), null);
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
/// false when the ecs or the world pointer is null, when the ECS refuses the component, or when the
/// world refuses its fields.
export fn ke_audio_register_scene_apply(ecs: ?*c.ke_ecs, world: ?*c.ke_world) callconv(.c) bool {
    const e = ecs orelse return false;
    const w = world orelse return false;

    const player_cid = registerComponent(
        e,
        c.KE_COMPONENT_NAME_AUDIO_PLAYER,
        c.ke_audio_player_component,
        &c.ke_audio_player_component_fields,
    );
    if (player_cid == c.KE_COMPONENT_INVALID) return false;
    return registerFields(w, player_cid, &c.ke_audio_player_component_fields);
}

const std = @import("std");
const testing = std.testing;
const Stubs = @import("stubs").Stubs(c);

const FakeWorld = struct {
    api: c.ke_world,
    accepts: bool,
    registered_cid: c.ke_component_id = c.KE_COMPONENT_INVALID,
    field_count: u32 = 0,

    fn init(self: *FakeWorld, accepts: bool) void {
        self.* = .{ .api = std.mem.zeroes(c.ke_world), .accepts = accepts };
        self.api.handle = self;
        self.api.register_component_fields = &registerComponentFields;
    }

    fn registerComponentFields(self: ?*c.ke_world, cid: c.ke_component_id, _: [*c]const c.ke_component_field,
                               count: u32, _: [*c][*c]c.ke_error) callconv(.c) bool {
        const w: *FakeWorld = @ptrCast(@alignCast(self.?.handle));
        if (!w.accepts) return false;
        w.registered_cid = cid;
        w.field_count = count;
        return true;
    }
};

test "the audio player component is registered with the ecs and its fields with the world" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var world: FakeWorld = undefined;
    world.init(true);

    try testing.expect(ke_audio_register_scene_apply(ecs.api(), &world.api));
    try testing.expect(world.registered_cid != c.KE_COMPONENT_INVALID);
    try testing.expectEqual(@as(u32, c.ke_audio_player_component_fields.len), world.field_count);
}

test "a world that refuses the fields, or a missing ecs or world, fails the registration" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var world: FakeWorld = undefined;
    world.init(false);

    try testing.expect(!ke_audio_register_scene_apply(ecs.api(), &world.api));
    try testing.expect(!ke_audio_register_scene_apply(null, &world.api));
    try testing.expect(!ke_audio_register_scene_apply(ecs.api(), null));
}
