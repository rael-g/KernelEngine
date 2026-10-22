//! The set of audio's scene components, so a scene file can author an audio player.

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @import("c");
const scene_components = @import("scene_components");

const Components = scene_components.Set(c, &.{
    .{ .name = c.KE_COMPONENT_NAME_AUDIO_PLAYER, .size = @sizeOf(c.ke_audio_player_component), .alignment = @alignOf(c.ke_audio_player_component), .fields = &c.ke_audio_player_component_fields },
});

/// The factory. The set holds no state, so it cannot fail.
export fn ke_audio_scene_components_create() callconv(.c) c.ke_scene_component_set_handle {
    return Components.handle();
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

    const set = ke_audio_scene_components_create();
    defer set.destroy.?(set.ref);
    try testing.expect(set.ref.*.register_into.?(set.ref, ecs.api(), &world.api, null));
    try testing.expect(world.registered_cid != c.KE_COMPONENT_INVALID);
    try testing.expectEqual(@as(u32, c.ke_audio_player_component_fields.len), world.field_count);
}

test "a world that refuses the fields, or a missing ecs or world, fails the registration" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var world: FakeWorld = undefined;
    world.init(false);

    const set = ke_audio_scene_components_create();
    defer set.destroy.?(set.ref);
    try testing.expect(!set.ref.*.register_into.?(set.ref, ecs.api(), &world.api, null));
    var err: [*c]c.ke_error = null;
    try testing.expect(!set.ref.*.register_into.?(set.ref, null, &world.api, &err));
    try testing.expect(err != null);
    try testing.expect(!set.ref.*.register_into.?(set.ref, ecs.api(), null, null));
}
