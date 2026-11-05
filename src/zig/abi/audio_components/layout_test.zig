const std = @import("std");
const abi = @import("abi");
const c = @import("c");

fn expectSameLayout(comptime A: type, comptime C: type) !void {
    @setEvalBranchQuota(100_000_000);
    if (@typeInfo(C) == .@"opaque") return;
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
    @setEvalBranchQuota(100_000_000);
    try expectSameLayout(abi.c.ke_sound_component, translated("ke_sound_component"));
    if (@hasDecl(c, "ke_audio_sound")) try expectSameLayout(abi.c.ke_audio_sound, c.ke_audio_sound);
    if (@hasDecl(c, "ke_audio_voice")) try expectSameLayout(abi.c.ke_audio_voice, c.ke_audio_voice);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_SOUND_RELEASE_KEEP), @as(i64, abi.c.KE_SOUND_RELEASE_KEEP));
    try std.testing.expectEqual(@as(i64, c.KE_SOUND_RELEASE_WHEN_DONE), @as(i64, abi.c.KE_SOUND_RELEASE_WHEN_DONE));
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_SOUND_MAX_PATH), @as(i128, abi.c.KE_SOUND_MAX_PATH));
}

extern const layout_values: [10]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_sound_component),
        @offsetOf(abi.c.ke_sound_component, "path"),
        @offsetOf(abi.c.ke_sound_component, "volume"),
        @offsetOf(abi.c.ke_sound_component, "pitch"),
        @offsetOf(abi.c.ke_sound_component, "loop"),
        @offsetOf(abi.c.ke_sound_component, "playing"),
        @offsetOf(abi.c.ke_sound_component, "release"),
        @offsetOf(abi.c.ke_sound_component, "clip"),
        @offsetOf(abi.c.ke_sound_component, "voice"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
