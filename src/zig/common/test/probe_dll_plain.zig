//! A probe DLL with the same two exported accessors as probe_dll_fixed.zig and no re-export of the
//! entry point, so it relies on Zig's own DLL entry point.

const std = @import("std");

extern fn ke_probe_ctor_ran() c_int;
extern fn ke_probe_marker() [*c]const u8;

export fn ke_ctor_ran() callconv(.c) c_int {
    return ke_probe_ctor_ran();
}

export fn ke_marker() callconv(.c) [*c]const u8 {
    return ke_probe_marker();
}
