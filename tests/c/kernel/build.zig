const std = @import("std");

// Builds test_ke_kernel by invoking the SYSTEM C++ compiler directly — see
// tests/integration/cpp/build.zig for why (ABI mismatch between Zig's own
// libc++ and the libstdc++ vcpkg's GTest archives were built with). Zig is
// the build orchestrator here; the compile+link is the same system compiler
// CMake already used.

pub fn build(b: *std.Build) void {
    const cxx = b.option([]const u8, "cxx", "C++ compiler") orelse "clang++";
    const sources = b.option([]const u8, "sources", "'|'-separated absolute .cpp source paths") orelse @panic("-Dsources required");
    const include_dirs = b.option([]const u8, "include-dirs", "'|'-separated include directories") orelse @panic("-Dinclude-dirs required");
    const libs = b.option([]const u8, "libs", "'|'-separated absolute library file paths, in link order") orelse @panic("-Dlibs required");
    const rpaths = b.option([]const u8, "rpaths", "'|'-separated rpath directories") orelse @panic("-Drpaths required");
    const defines = b.option([]const u8, "defines", "'|'-separated -D defines") orelse "";
    const output = b.option([]const u8, "output", "absolute path for the built executable") orelse @panic("-Doutput required");

    const run = b.addSystemCommand(&.{ cxx, "-std=gnu++17", "-fPIE" });

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
