//! Builds the text keys under which the resolve systems cache the GPU objects they create.

const std = @import("std");

/// Owns the storage its key text is written into. The text sits in `buf`, sized at compile time
/// from the prefix and the field count, so building a key never allocates.
pub fn Key(comptime prefix: []const u8, comptime field_count: usize) type {
    return struct {
        const Self = @This();
        const len = prefix.len + field_count * 9;

        buf: [len + 1]u8 = undefined,

        /// Writes the prefix, then each 32-bit field as a colon and eight lowercase hex digits,
        /// and ends with a zero byte so the result is a C string. Equal inputs give equal text.
        /// Overwrites `buf` on every call, so a pointer returned by an earlier call is invalid
        /// once this one has run, and the pointer is valid only while this value stays in place.
        pub fn init(self: *Self, fields: [field_count]u32) [*:0]const u8 {
            @memcpy(self.buf[0..prefix.len], prefix);
            var at = prefix.len;
            for (fields) |v| {
                self.buf[at] = ':';
                writeHex32(self.buf[at + 1 ..][0..8], v);
                at += 9;
            }
            self.buf[len] = 0;
            return @ptrCast(&self.buf);
        }
    };
}

/// Returns the bit pattern of the float, so floats that print alike but differ in the last
/// mantissa bit still give different keys.
pub fn bits(v: f32) u32 {
    return @bitCast(v);
}

fn writeHex32(out: *[8]u8, v: u32) void {
    const digits = "0123456789abcdef";
    var x = v;
    var i: usize = 8;
    while (i > 0) {
        i -= 1;
        out[i] = digits[x & 0xf];
        x >>= 4;
    }
}

const testing = std.testing;

test "a key is the prefix followed by one fixed-width field each" {
    var k: Key("sprite", 2) = .{};
    const s = k.init(.{ 0x1, 0xdeadbeef });
    try testing.expectEqualStrings("sprite:00000001:deadbeef", std.mem.span(s));
}

test "a key of the widest possible fields still fits its own buffer" {
    var k: Key("inline", 8) = .{};
    const s = k.init(.{std.math.maxInt(u32)} ** 8);
    try testing.expectEqual(@as(usize, "inline".len + 8 * 9), std.mem.span(s).len);
}

test "two floats that print the same but differ in the mantissa get different keys" {
    const a: f32 = 1.0000001;
    const b: f32 = 1.0000002;
    var ka: Key("m", 1) = .{};
    var kb: Key("m", 1) = .{};
    const sa = std.mem.span(ka.init(.{bits(a)}));
    var kb_buf: [64]u8 = undefined;
    const sb = std.mem.span(kb.init(.{bits(b)}));
    @memcpy(kb_buf[0..sb.len], sb);
    try testing.expect(!std.mem.eql(u8, sa, kb_buf[0..sb.len]));
}

test "the same value always produces the same key" {
    var a: Key("q", 3) = .{};
    var b: Key("q", 3) = .{};
    const sa = a.init(.{ bits(2.5), bits(-0.25), 7 });
    var copy: [64]u8 = undefined;
    const span_a = std.mem.span(sa);
    @memcpy(copy[0..span_a.len], span_a);
    const sb = std.mem.span(b.init(.{ bits(2.5), bits(-0.25), 7 }));
    try testing.expectEqualStrings(copy[0..span_a.len], sb);
}
