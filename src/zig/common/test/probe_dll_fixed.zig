//! A probe DLL that re-exports the mingw entry point from the kerror module, and exports two
//! accessors, whose results come from the C++ probe code.

const std = @import("std");

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

extern fn ke_probe_ctor_ran() c_int;
extern fn ke_probe_marker() [*c]const u8;

export fn ke_ctor_ran() callconv(.c) c_int {
    return ke_probe_ctor_ran();
}

export fn ke_marker() callconv(.c) [*c]const u8 {
    return ke_probe_marker();
}
