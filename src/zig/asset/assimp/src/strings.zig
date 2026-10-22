//! Copies text into the fixed-size name fields of the loader's records.

const std = @import("std");

/// Copies a C string into a fixed buffer, cut to fit and always terminated. A null source leaves
/// an empty string, and a zero-length destination is left untouched.
pub fn copyString(dst: []u8, src: [*c]const u8) void {
    if (dst.len == 0) return;
    if (src == null) {
        dst[0] = 0;
        return;
    }
    const text = std.mem.span(src);
    const n = @min(text.len, dst.len - 1);
    @memcpy(dst[0..n], text[0..n]);
    dst[n] = 0;
}
