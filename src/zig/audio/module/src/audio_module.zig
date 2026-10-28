//! The set of audio's scene components, so a scene file can author an audio player.

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_audio_module").logFn };

const abi_audio = @import("abi_audio");
const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_result = @import("abi_result");
const scene_components = @import("scene_components");

const Components = scene_components.Set(&.{
    .{ .name = abi_audio.KE_COMPONENT_NAME_AUDIO_PLAYER, .size = @sizeOf(abi_audio.ke_audio_player_component), .alignment = @alignOf(abi_audio.ke_audio_player_component), .fields = &abi_audio.ke_audio_player_component_fields },
});

/// The factory. The set holds no state, so it cannot fail.
export fn ke_audio_scene_components_create() callconv(.c) abi_framework.ke_scene_component_set_handle {
    return Components.handle();
}

const std = @import("std");
const testing = std.testing;
const Stubs = @import("stubs");

const FakeWorld = struct {
    api: abi_framework.ke_world,
    accepts: bool,
    registered_cid: abi_ecs.ke_component_id = abi_ecs.KE_COMPONENT_INVALID,
    field_count: u32 = 0,

    fn init(self: *FakeWorld, accepts: bool) void {
        self.* = .{ .api = std.mem.zeroes(abi_framework.ke_world), .accepts = accepts };
        self.api.handle = self;
        self.api.register_component_fields = &registerComponentFields;
    }

    fn registerComponentFields(self: ?*abi_framework.ke_world, cid: abi_ecs.ke_component_id, _: [*c]const abi_ecs.ke_component_field,
                               count: u32) callconv(.c) abi_result.ke_result {
        const w: *FakeWorld = @ptrCast(@alignCast(self.?.handle));
        if (!w.accepts) return abi_result.KE_RESULT_GENERAL;
        w.registered_cid = cid;
        w.field_count = count;
        return abi_result.KE_OK;
    }
};

test "the audio player component is registered with the ecs and its fields with the world" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var world: FakeWorld = undefined;
    world.init(true);

    const set = ke_audio_scene_components_create();
    defer set.destroy.?(set.ref);
    try testing.expectEqual(@as(abi_result.ke_result, abi_result.KE_OK), set.ref.?.register_into.?(set.ref, ecs.api(), &world.api));
    try testing.expect(world.registered_cid != abi_ecs.KE_COMPONENT_INVALID);
    try testing.expectEqual(@as(u32, abi_audio.ke_audio_player_component_fields.len), world.field_count);
}

test "a world that refuses the fields, or a missing ecs or world, fails the registration" {
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var world: FakeWorld = undefined;
    world.init(false);

    const set = ke_audio_scene_components_create();
    defer set.destroy.?(set.ref);
    try testing.expectEqual(@as(abi_result.ke_result, abi_result.KE_RESULT_GENERAL), set.ref.?.register_into.?(set.ref, ecs.api(), &world.api));
    try testing.expectEqual(@as(abi_result.ke_result, abi_result.KE_RESULT_INVALID_ARGUMENT), set.ref.?.register_into.?(set.ref, null, &world.api));
    try testing.expectEqual(@as(abi_result.ke_result, abi_result.KE_RESULT_INVALID_ARGUMENT), set.ref.?.register_into.?(set.ref, ecs.api(), null));
}
