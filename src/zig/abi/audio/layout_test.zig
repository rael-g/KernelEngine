const std = @import("std");
const abi = @import("abi");
const c = @import("c");

fn expectSameLayout(comptime A: type, comptime C: type) !void {
    try std.testing.expectEqual(@sizeOf(C), @sizeOf(A));
    try std.testing.expectEqual(@alignOf(C), @alignOf(A));
    switch (@typeInfo(A)) {
        .@"struct" => |s| inline for (s.fields) |f| {
            try std.testing.expectEqual(@offsetOf(C, f.name), @offsetOf(A, f.name));
            try expectSameLayout(f.type, @FieldType(C, f.name));
        },
        .@"union" => |u| inline for (u.fields) |f| try expectSameLayout(f.type, @FieldType(C, f.name)),
        else => {},
    }
}

fn translated(comptime name: []const u8) type {
    return if (@hasDecl(c, name)) @field(c, name) else @field(c, "struct_" ++ name);
}

test "every record is laid out as the header lays it out" {
    try expectSameLayout(abi.ke_audio_player_component, translated("ke_audio_player_component"));
    try expectSameLayout(abi.ke_audio, translated("ke_audio"));
    try expectSameLayout(abi.ke_audio_handle, translated("ke_audio_handle"));
    try expectSameLayout(abi.ke_audio_sound, c.ke_audio_sound);
}

fn expectSameValue(a: anytype, k: anytype) !void {
    switch (@typeInfo(@TypeOf(a))) {
        .@"struct" => |s| inline for (s.fields) |f| try expectSameValue(@field(a, f.name), @field(k, f.name)),
        .@"union" => {},
        .optional => try std.testing.expectEqualStrings(std.mem.span(k), std.mem.span(a.?)),
        else => try std.testing.expectEqual(@as(@TypeOf(a), k), a),
    }
}

test "every field table lists the header's entries" {
    try std.testing.expectEqual(c.ke_audio_player_component_fields.len, abi.ke_audio_player_component_fields.len);
    for (abi.ke_audio_player_component_fields, c.ke_audio_player_component_fields) |a, k| try expectSameValue(a, k);
}

test "every constant is the header's value" {
    try std.testing.expectEqual(@as(i128, c.KE_AUDIO_SOUND_INVALID), @as(i128, abi.KE_AUDIO_SOUND_INVALID));
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_AUDIO_PLAYER, abi.KE_COMPONENT_NAME_AUDIO_PLAYER);
    try std.testing.expectEqual(@as(i128, c.KE_AUDIO_PLAYER_MAX_PATH), @as(i128, abi.KE_AUDIO_PLAYER_MAX_PATH));
}
