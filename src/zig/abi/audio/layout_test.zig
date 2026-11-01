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
    try expectSameLayout(abi.c.ke_audio, translated("ke_audio"));
    try expectSameLayout(abi.c.ke_audio_handle, translated("ke_audio_handle"));
    if (@hasDecl(c, "ke_audio_sound")) try expectSameLayout(abi.c.ke_audio_sound, c.ke_audio_sound);
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_AUDIO_SOUND_INVALID), @as(i128, abi.c.KE_AUDIO_SOUND_INVALID));
}

extern const layout_values: [11]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_audio),
        @offsetOf(abi.c.ke_audio, "handle"),
        @offsetOf(abi.c.ke_audio, "load_sound"),
        @offsetOf(abi.c.ke_audio, "unload_sound"),
        @offsetOf(abi.c.ke_audio, "play"),
        @offsetOf(abi.c.ke_audio, "stop"),
        @offsetOf(abi.c.ke_audio, "set_master_volume"),
        @sizeOf(abi.c.ke_audio_handle),
        @offsetOf(abi.c.ke_audio_handle, "ref"),
        @offsetOf(abi.c.ke_audio_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
