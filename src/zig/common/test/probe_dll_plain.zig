//! A probe DLL that relies on Zig's own DLL entry point, for the entry point test.

const std = @import("std");

extern fn ke_probe_ctor_ran() c_int;
extern fn ke_probe_marker() [*c]const u8;

export fn ke_ctor_ran() callconv(.c) c_int {
    return ke_probe_ctor_ran();
}

export fn ke_marker() callconv(.c) [*c]const u8 {
    return ke_probe_marker();
}
