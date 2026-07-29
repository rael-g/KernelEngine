// Probe DLL *without* the mingw-entry-point workaround — i.e. what a plugin
// looks like if someone writes one and forgets, or if the workaround is
// removed. Identical to probe_dll_fixed.zig except for the missing
// `_DllMainCRTStartup` re-export, so the pair isolates exactly that one line.
//
// This is the canary half: dll_crt_init_test.zig asserts this DLL's C++ global
// constructors do NOT run. When that assertion starts failing, Zig has fixed
// the underlying defect and the workaround can be retired.

const std = @import("std");

extern fn ke_probe_ctor_ran() c_int;
extern fn ke_probe_marker() [*c]const u8;

export fn ke_ctor_ran() callconv(.c) c_int {
    return ke_probe_ctor_ran();
}

export fn ke_marker() callconv(.c) [*c]const u8 {
    return ke_probe_marker();
}
