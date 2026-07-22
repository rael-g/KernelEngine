const std = @import("std");

// Builds test_integration_cpp by invoking the SYSTEM C++ compiler directly —
// not Zig's own C++ frontend. These are real GTest binaries linking vcpkg's
// GTest archives, which were compiled with the system toolchain's libstdc++;
// Zig's bundled C++ frontend links its own libc++ instead, an incompatible
// ABI for the std::string/std::ostream types that cross the gtest boundary
// (confirmed by hand: linking failed with std::__1::* vs std::__cxx11::*
// symbol mismatches). So Zig is the build orchestrator here, replacing
// CMake's role, while the actual compile+link is the same system compiler
// CMake already invoked — same includes, same libraries, same flags.
//
// All the multi-value options below are "|"-separated single strings rather
// than repeated flags, matching the convention already used for Assimp's
// dependency chain in src/zig/asset/assimp/CMakeLists.txt.

pub fn build(b: *std.Build) void {
    const cxx = b.option([]const u8, "cxx", "C++ compiler") orelse "clang++";
    const sources = b.option([]const u8, "sources", "'|'-separated absolute .cpp source paths") orelse @panic("-Dsources required");
    const include_dirs = b.option([]const u8, "include-dirs", "'|'-separated include directories") orelse @panic("-Dinclude-dirs required");
    const libs = b.option([]const u8, "libs", "'|'-separated absolute library file paths, in link order") orelse @panic("-Dlibs required");
    const rpaths = b.option([]const u8, "rpaths", "'|'-separated rpath directories") orelse @panic("-Drpaths required");
    const defines = b.option([]const u8, "defines", "'|'-separated -D defines") orelse "";
    const output = b.option([]const u8, "output", "absolute path for the built executable") orelse @panic("-Doutput required");
    // See tests/c/kernel/build.zig for why this only reaches this suite's own
    // translation units, not the engine logic inside the linked ke_*.so
    // plugins (those are Zig-linked; Zig's linker rejects Clang's profiling
    // relocations).
    const coverage = b.option(bool, "coverage", "instrument this suite's own sources for Clang source-based coverage") orelse false;

    const run = b.addSystemCommand(&.{ cxx, "-std=gnu++17", "-fPIE" });
    if (coverage) run.addArgs(&.{ "-fprofile-instr-generate", "-fcoverage-mapping" });

    var def_it = std.mem.splitScalar(u8, defines, '|');
    while (def_it.next()) |d| {
        if (d.len != 0) run.addArg(b.fmt("-D{s}", .{d}));
    }

    var inc_it = std.mem.splitScalar(u8, include_dirs, '|');
    while (inc_it.next()) |inc| {
        if (inc.len != 0) run.addArg(b.fmt("-I{s}", .{inc}));
    }

    var src_it = std.mem.splitScalar(u8, sources, '|');
    while (src_it.next()) |src| {
        if (src.len != 0) run.addArg(src);
    }

    run.addArgs(&.{ "-o", output });

    var rpath_it = std.mem.splitScalar(u8, rpaths, '|');
    while (rpath_it.next()) |rp| {
        if (rp.len != 0) run.addArg(b.fmt("-Wl,-rpath,{s}", .{rp}));
    }

    var lib_it = std.mem.splitScalar(u8, libs, '|');
    while (lib_it.next()) |lib| {
        if (lib.len != 0) run.addArg(lib);
    }

    b.getInstallStep().dependOn(&run.step);
}
