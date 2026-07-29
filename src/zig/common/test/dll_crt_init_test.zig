// Guards the Windows DLL entry-point workaround in kerror.zig from both sides.
//
// Two probe DLLs are built from identical sources, differing only in whether
// they re-export mingw's `_DllMainCRTStartup` (probe_dll_fixed.zig does,
// probe_dll_plain.zig does not). Each links a C++ translation unit whose global
// constructor sets a value; reading that value back says whether the CRT ran
// the C++ initializer section at DLL attach.
//
//   - The regression half asserts the *fixed* DLL constructs its globals. It
//     fails if the workaround is dropped or stops working, which would
//     otherwise surface as a segfault deep inside Assimp with nothing pointing
//     back here.
//
//   - The canary half asserts the *plain* DLL does NOT construct them, pinning
//     down that the workaround is still load-bearing. When a future Zig release
//     performs the mingw CRT bring-up in its own DLL entry, this assertion
//     starts failing — that failure is the signal to delete the workaround (the
//     `_DllMainCRTStartup` re-export in every plugin root plus the decl in
//     kerror.zig) and these probes along with it. Its message says so.
//
// Windows-only: on other targets Zig's DLL entry point is not in play at all.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const build_options = @import("build_options");

// std.DynLib has no Windows backend in Zig 0.16, so the loader is spelled out
// against kernel32 directly. LoadLibrary is what actually matters here: it is
// the call that triggers the DLL entry point whose behaviour is under test.
extern "kernel32" fn LoadLibraryA(path: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) c_int;
extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;

const CtorRanFn = *const fn () callconv(.c) c_int;
const MarkerFn = *const fn () callconv(.c) [*c]const u8;

const Probe = struct {
    module: *anyopaque,

    fn load(path: []const u8) !Probe {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const path_z = try std.fmt.bufPrintZ(&buf, "{s}", .{path});
        return .{ .module = LoadLibraryA(path_z) orelse return error.DllLoadFailed };
    }

    fn unload(self: Probe) void {
        _ = FreeLibrary(self.module);
    }

    fn ctorRan(self: Probe) !c_int {
        const sym = GetProcAddress(self.module, "ke_ctor_ran") orelse return error.SymbolNotFound;
        return @as(CtorRanFn, @ptrCast(sym))();
    }

    fn marker(self: Probe) ![]const u8 {
        const sym = GetProcAddress(self.module, "ke_marker") orelse return error.SymbolNotFound;
        return std.mem.span(@as(MarkerFn, @ptrCast(sym))());
    }
};

test "a plugin DLL that re-exports mingw's entry point runs its C++ static initializers" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const probe = try Probe.load(build_options.probe_dll_fixed);
    defer probe.unload();

    try testing.expectEqual(@as(c_int, 1), try probe.ctorRan());
    try testing.expectEqualStrings("constructed", try probe.marker());
}

test "canary: without the re-export Zig's stub entry point still skips them" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const probe = try Probe.load(build_options.probe_dll_plain);
    defer probe.unload();

    const ran = try probe.ctorRan();
    if (ran != 0) {
        std.debug.print(
            \\
            \\This test failing is good news, not a regression.
            \\
            \\A Zig DLL built WITHOUT the `_DllMainCRTStartup` re-export just ran its
            \\C++ static initializers, which means Zig's own DLL entry point now
            \\performs the mingw CRT bring-up it used to skip. The workaround is no
            \\longer load-bearing and should be retired:
            \\
            \\  1. drop `pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;`
            \\     from every plugin root module that has it,
            \\  2. drop the `_DllMainCRTStartup` decl from src/zig/common/kerror.zig,
            \\  3. delete src/zig/common/test/ (these probes) and their build wiring.
            \\
            \\Re-run the native test suites afterwards — Assimp model loading is the
            \\case that regressed hardest without it.
            \\
        , .{});
        return error.WorkaroundNoLongerNeeded;
    }
}
