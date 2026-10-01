const std = @import("std");

pub fn Fields(comptime c: type) type {
    return struct {
        fn asFloat(v: *const c.ke_variant) ?f32 {
            return switch (v.type) {
                c.KE_VARIANT_FLOAT => @floatCast(v.unnamed_0.f),
                c.KE_VARIANT_INT => @floatFromInt(v.unnamed_0.i),
                else => null,
            };
        }

        fn asInt(v: *const c.ke_variant) ?i64 {
            return switch (v.type) {
                c.KE_VARIANT_INT => v.unnamed_0.i,
                c.KE_VARIANT_FLOAT => std.math.lossyCast(i64, v.unnamed_0.f),
                c.KE_VARIANT_BOOL => @intFromBool(v.unnamed_0.b),
                else => null,
            };
        }

        fn asBool(v: *const c.ke_variant) ?i64 {
            return switch (v.type) {
                c.KE_VARIANT_BOOL => @intFromBool(v.unnamed_0.b),
                c.KE_VARIANT_INT => @intFromBool(v.unnamed_0.i != 0),
                else => null,
            };
        }

        fn asVec4(v: *const c.ke_variant) ?c.ke_vec4 {
            return switch (v.type) {
                c.KE_VARIANT_VEC4 => v.unnamed_0.v4,
                c.KE_VARIANT_QUAT => .{ .x = v.unnamed_0.q.x, .y = v.unnamed_0.q.y, .z = v.unnamed_0.q.z, .w = v.unnamed_0.q.w },
                c.KE_VARIANT_VEC3 => .{ .x = v.unnamed_0.v3.x, .y = v.unnamed_0.v3.y, .z = v.unnamed_0.v3.z, .w = 1.0 },
                else => null,
            };
        }

        fn asVec3(v: *const c.ke_variant) ?c.ke_vec3 {
            return switch (v.type) {
                c.KE_VARIANT_VEC3 => v.unnamed_0.v3,
                c.KE_VARIANT_VEC4 => .{ .x = v.unnamed_0.v4.x, .y = v.unnamed_0.v4.y, .z = v.unnamed_0.v4.z },
                c.KE_VARIANT_VEC2 => .{ .x = v.unnamed_0.v2.x, .y = v.unnamed_0.v2.y, .z = 0.0 },
                else => null,
            };
        }

        fn asVec2(v: *const c.ke_variant) ?c.ke_vec2 {
            return switch (v.type) {
                c.KE_VARIANT_VEC2 => v.unnamed_0.v2,
                c.KE_VARIANT_VEC3 => .{ .x = v.unnamed_0.v3.x, .y = v.unnamed_0.v3.y },
                c.KE_VARIANT_VEC4 => .{ .x = v.unnamed_0.v4.x, .y = v.unnamed_0.v4.y },
                else => null,
            };
        }

        fn writeBytes(base: [*]u8, field: *const c.ke_component_field, src: []const u8) void {
            if (src.len != field.size) return;
            @memcpy(base[field.offset..][0..src.len], src);
        }

        fn writeValue(base: [*]u8, field: *const c.ke_component_field, value: anytype) void {
            writeBytes(base, field, std.mem.asBytes(&value));
        }

        fn writeInt(base: [*]u8, field: *const c.ke_component_field, value: i64) void {
            switch (field.size) {
                1 => writeBytes(base, field, std.mem.asBytes(&@as(u8, @truncate(@as(u64, @bitCast(value)))))),
                2 => writeBytes(base, field, std.mem.asBytes(&@as(u16, @truncate(@as(u64, @bitCast(value)))))),
                4 => writeBytes(base, field, std.mem.asBytes(&@as(u32, @truncate(@as(u64, @bitCast(value)))))),
                8 => writeBytes(base, field, std.mem.asBytes(&@as(u64, @bitCast(value)))),
                else => {},
            }
        }

        pub fn write(component: ?*anyopaque, field: ?*const c.ke_component_field, value: ?*const c.ke_variant) void {
            const base: [*]u8 = @ptrCast(component orelse return);
            const f = field orelse return;
            const v = value orelse return;

            switch (f.type) {
                c.KE_VARIANT_FLOAT => {
                    const x = asFloat(v) orelse return;
                    if (f.size == 4) {
                        writeValue(base, f, x);
                    } else if (f.size == 8) {
                        writeValue(base, f, @as(f64, x));
                    }
                },
                c.KE_VARIANT_INT => {
                    const x = asInt(v) orelse return;
                    writeInt(base, f, x);
                },
                c.KE_VARIANT_BOOL => {
                    const x = asBool(v) orelse return;
                    writeInt(base, f, x);
                },
                c.KE_VARIANT_VEC2 => {
                    const x = asVec2(v) orelse return;
                    writeValue(base, f, x);
                },
                c.KE_VARIANT_VEC3 => {
                    const x = asVec3(v) orelse return;
                    writeValue(base, f, x);
                },
                c.KE_VARIANT_VEC4, c.KE_VARIANT_QUAT => {
                    const x = asVec4(v) orelse return;
                    writeValue(base, f, x);
                },
                c.KE_VARIANT_STRING => {
                    if (v.type != c.KE_VARIANT_STRING or v.unnamed_0.s == null or f.size == 0) return;
                    const src = std.mem.span(v.unnamed_0.s);
                    const n = @min(src.len, @as(usize, f.size) - 1);
                    @memcpy(base[f.offset..][0..n], src[0..n]);
                    base[f.offset + n] = 0;
                },
                else => {},
            }
        }

        pub fn seedDefaults(component: ?*anyopaque, fields: ?[*]const c.ke_component_field, field_count: u32) void {
            if (component == null) return;
            const table = fields orelse return;
            for (table[0..field_count]) |*f| {
                if (f.default_value.type == c.KE_VARIANT_NULL) continue;
                write(component, f, &f.default_value);
            }
        }
    };
}
