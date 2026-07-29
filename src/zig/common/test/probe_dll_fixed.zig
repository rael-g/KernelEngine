// Probe DLL *with* the mingw-entry-point workaround applied — the shape every
// engine plugin that links C/C++ uses. Its counterpart is probe_dll_plain.zig.
// See kerror.zig's `_DllMainCRTStartup` doc comment for what this works around,
// and dll_crt_init_test.zig for what the pair proves.

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
