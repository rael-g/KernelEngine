//! Audio's scene components, added to the set the host hands in, so a scene file can author an
//! audio player.

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_audio_module").logFn };

const abi_audio = @import("abi_audio");
const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_result = @import("abi_result");

const components = [_]abi_ecs.ke_component_params{
    .{ .name = abi_audio.KE_COMPONENT_NAME_AUDIO_PLAYER, .size = @sizeOf(abi_audio.ke_audio_player_component), .alignment = @alignOf(abi_audio.ke_audio_player_component), .fields = &abi_audio.ke_audio_player_component_fields, .field_count = abi_audio.ke_audio_player_component_fields.len },
};

/// The factory. Adds the components in order and stops at the first one the set refuses.
export fn ke_audio_scene_components_create(set_in: ?*abi_framework.ke_scene_component_set) callconv(.c) abi_result.ke_result {
    const set = set_in orelse return abi_result.KE_RESULT_INVALID_ARGUMENT;
    for (&components) |*component| {
        const added = set.add.?(set, component, null);
        if (added != abi_result.KE_OK) return added;
    }
    return abi_result.KE_OK;
}

const std = @import("std");
const testing = std.testing;

const FakeSet = struct {
    api: abi_framework.ke_scene_component_set,
    refuses: bool,
    names: [4][*:0]const u8 = undefined,
    field_counts: [4]u32 = undefined,
    count: usize = 0,

    fn init(self: *FakeSet, refuses: bool) void {
        self.* = .{ .api = std.mem.zeroes(abi_framework.ke_scene_component_set), .refuses = refuses };
        self.api.handle = self;
        self.api.add = &add;
    }

    fn add(self: ?*abi_framework.ke_scene_component_set, component: ?*const abi_ecs.ke_component_params, _: abi_framework.ke_component_apply_fn) callconv(.c) abi_result.ke_result {
        const s: *FakeSet = @ptrCast(@alignCast(self.?.handle));
        if (s.refuses) return abi_result.KE_RESULT_OUT_OF_MEMORY;
        s.names[s.count] = component.?.name.?;
        s.field_counts[s.count] = component.?.field_count;
        s.count += 1;
        return abi_result.KE_OK;
    }
};

test "the audio player is added to the set with its field table" {
    var set: FakeSet = undefined;
    set.init(false);
    try testing.expectEqual(@as(abi_result.ke_result, abi_result.KE_OK), ke_audio_scene_components_create(&set.api));
    try testing.expectEqual(@as(usize, 1), set.count);
    try testing.expectEqualStrings(abi_audio.KE_COMPONENT_NAME_AUDIO_PLAYER, std.mem.span(set.names[0]));
    try testing.expectEqual(@as(u32, abi_audio.ke_audio_player_component_fields.len), set.field_counts[0]);
}

test "a set that refuses a component, or a missing set, fails the factory" {
    var set: FakeSet = undefined;
    set.init(true);
    try testing.expectEqual(@as(abi_result.ke_result, abi_result.KE_RESULT_OUT_OF_MEMORY), ke_audio_scene_components_create(&set.api));
    try testing.expectEqual(@as(abi_result.ke_result, abi_result.KE_RESULT_INVALID_ARGUMENT), ke_audio_scene_components_create(null));
}
