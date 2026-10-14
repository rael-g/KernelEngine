//! Writes a variant into the memory of a component at the place one of its fields describes.
//! It holds no state and allocates nothing.

const std = @import("std");

/// Returns the component-writing functions for the contract types of `c`, the cimport it is
/// given. `write` converts between related variants and refuses anything else; a string is cut to
/// leave room for its terminating zero instead of being refused for its length.
pub fn Fields(comptime c: type) type {
    return struct {
        /// Accepts a float or an integer; any other variant has no float reading.
        fn asFloat(v: *const c.ke_variant) ?f32 {
            return switch (v.type) {
                c.KE_VARIANT_FLOAT => @floatCast(v.unnamed_0.f),
                c.KE_VARIANT_INT => @floatFromInt(v.unnamed_0.i),
                else => null,
            };
        }

        /// Accepts an integer, a float, which saturates, or a boolean; any other variant has no
        /// integer reading.
        fn asInt(v: *const c.ke_variant) ?i64 {
            return switch (v.type) {
                c.KE_VARIANT_INT => v.unnamed_0.i,
                c.KE_VARIANT_FLOAT => std.math.lossyCast(i64, v.unnamed_0.f),
                c.KE_VARIANT_BOOL => @intFromBool(v.unnamed_0.b),
                else => null,
            };
        }

        /// Accepts a boolean, or an integer, which is true when not zero, and yields 1 or 0 for
        /// the integer store.
        fn asBool(v: *const c.ke_variant) ?i64 {
            return switch (v.type) {
                c.KE_VARIANT_BOOL => @intFromBool(v.unnamed_0.b),
                c.KE_VARIANT_INT => @intFromBool(v.unnamed_0.i != 0),
                else => null,
            };
        }

        /// Accepts a four-component vector, a quaternion, or a three-component vector, which gains
        /// a last component of one.
        fn asVec4(v: *const c.ke_variant) ?c.ke_vec4 {
            return switch (v.type) {
                c.KE_VARIANT_VEC4 => v.unnamed_0.v4,
                c.KE_VARIANT_QUAT => .{ .x = v.unnamed_0.q.x, .y = v.unnamed_0.q.y, .z = v.unnamed_0.q.z, .w = v.unnamed_0.q.w },
                c.KE_VARIANT_VEC3 => .{ .x = v.unnamed_0.v3.x, .y = v.unnamed_0.v3.y, .z = v.unnamed_0.v3.z, .w = 1.0 },
                else => null,
            };
        }

        /// Accepts a three-component vector, a four-component one, which drops its last component,
        /// or a two-component one, which gains a last component of zero.
        fn asVec3(v: *const c.ke_variant) ?c.ke_vec3 {
            return switch (v.type) {
                c.KE_VARIANT_VEC3 => v.unnamed_0.v3,
                c.KE_VARIANT_VEC4 => .{ .x = v.unnamed_0.v4.x, .y = v.unnamed_0.v4.y, .z = v.unnamed_0.v4.z },
                c.KE_VARIANT_VEC2 => .{ .x = v.unnamed_0.v2.x, .y = v.unnamed_0.v2.y, .z = 0.0 },
                else => null,
            };
        }

        /// Accepts a two-component vector, or a wider one, which drops its extra components.
        fn asVec2(v: *const c.ke_variant) ?c.ke_vec2 {
            return switch (v.type) {
                c.KE_VARIANT_VEC2 => v.unnamed_0.v2,
                c.KE_VARIANT_VEC3 => .{ .x = v.unnamed_0.v3.x, .y = v.unnamed_0.v3.y },
                c.KE_VARIANT_VEC4 => .{ .x = v.unnamed_0.v4.x, .y = v.unnamed_0.v4.y },
                else => null,
            };
        }

        /// Copies the bytes to the field's offset only when their count is the field's size.
        fn writeBytes(base: [*]u8, field: *const c.ke_component_field, src: []const u8) bool {
            if (src.len != field.size) return false;
            @memcpy(base[field.offset..][0..src.len], src);
            return true;
        }

        fn writeValue(base: [*]u8, field: *const c.ke_component_field, value: anytype) bool {
            return writeBytes(base, field, std.mem.asBytes(&value));
        }

        /// Stores the low bytes of the integer when the field's size is one of the integer widths
        /// of one, two, four or eight bytes, and refuses any other size.
        fn writeInt(base: [*]u8, field: *const c.ke_component_field, value: i64) bool {
            return switch (field.size) {
                1 => writeBytes(base, field, std.mem.asBytes(&@as(u8, @truncate(@as(u64, @bitCast(value)))))),
                2 => writeBytes(base, field, std.mem.asBytes(&@as(u16, @truncate(@as(u64, @bitCast(value)))))),
                4 => writeBytes(base, field, std.mem.asBytes(&@as(u32, @truncate(@as(u64, @bitCast(value)))))),
                8 => writeBytes(base, field, std.mem.asBytes(&@as(u64, @bitCast(value)))),
                else => false,
            };
        }

        /// Stores the value into the place the field describes inside the component, converted to
        /// the field's declared type. Returns false, and stores nothing, when the component, the
        /// field or the value pointer is null, when the value's variant type does not convert to
        /// the declared type, or when the field's size does not fit that type.
        pub fn write(component: ?*anyopaque, field: ?*const c.ke_component_field, value: ?*const c.ke_variant) bool {
            const base: [*]u8 = @ptrCast(component orelse return false);
            const f = field orelse return false;
            const v = value orelse return false;

            switch (f.type) {
                c.KE_VARIANT_FLOAT => {
                    const x = asFloat(v) orelse return false;
                    if (f.size == 4) return writeValue(base, f, x);
                    if (f.size == 8) return writeValue(base, f, @as(f64, x));
                    return false;
                },
                c.KE_VARIANT_INT => {
                    const x = asInt(v) orelse return false;
                    return writeInt(base, f, x);
                },
                c.KE_VARIANT_BOOL => {
                    const x = asBool(v) orelse return false;
                    return writeInt(base, f, x);
                },
                c.KE_VARIANT_VEC2 => {
                    const x = asVec2(v) orelse return false;
                    return writeValue(base, f, x);
                },
                c.KE_VARIANT_VEC3 => {
                    const x = asVec3(v) orelse return false;
                    return writeValue(base, f, x);
                },
                c.KE_VARIANT_VEC4, c.KE_VARIANT_QUAT => {
                    const x = asVec4(v) orelse return false;
                    return writeValue(base, f, x);
                },
                c.KE_VARIANT_STRING => {
                    if (v.type != c.KE_VARIANT_STRING or v.unnamed_0.s == null or f.size == 0) return false;
                    const src = std.mem.span(v.unnamed_0.s);
                    const n = @min(src.len, @as(usize, f.size) - 1);
                    @memcpy(base[f.offset..][0..n], src[0..n]);
                    base[f.offset + n] = 0;
                    return true;
                },
                else => return false,
            }
        }

        /// Stores the default of each field among the first entries of the table, as many as the
        /// count gives, through `write`. Defaults of the null variant are skipped. A default that
        /// `write` refuses is passed over with no report, and its field keeps the bytes it held.
        pub fn seedDefaults(component: ?*anyopaque, fields: ?[*]const c.ke_component_field, field_count: u32) void {
            if (component == null) return;
            const table = fields orelse return;
            for (table[0..field_count]) |*f| {
                if (f.default_value.type == c.KE_VARIANT_NULL) continue;
                _ = write(component, f, &f.default_value);
            }
        }
    };
}
