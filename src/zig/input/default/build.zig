const std = @import("std");

// Build the ke_input_default shared library (Zig 0.16 API) — a kernel built-in
// (keyboard/mouse state + event queue). Pure logic: no third-party C, no vcpkg
// lib. Allocates through Zig's own allocator; ke_common is consumed across a
// plain C-ABI DLL boundary (ABI-neutral).

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_input = b.option([]const u8, "ke-input-include", "kernel_engine/input include dir") orelse @panic("-Dke-input-include required");

    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/input_default.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_input }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    const kerror_mod = b.createModule(.{ .root_source_file = .{ .cwd_relative = kerror_src }, .target = target, .optimize = optimize });
    mod.addImport("kerror", kerror_mod);
    mod.addCMacro("KE_INPUT_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_input_default",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
