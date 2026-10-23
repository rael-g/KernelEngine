//! The mingw DLL entry point, declared so that a plugin root can re-export it. A workaround: Zig's
//! own DLL entry point does not run the static initializers of linked C and C++ libraries, and the
//! re-export is what makes them run.

const std = @import("std");

/// The entry point of the mingw C runtime, which runs the static initializers before the DLL's
/// own code.
pub extern fn _DllMainCRTStartup(
    hinst: std.os.windows.HINSTANCE,
    reason: std.os.windows.DWORD,
    reserved: std.os.windows.LPVOID,
) callconv(.winapi) std.os.windows.BOOL;
