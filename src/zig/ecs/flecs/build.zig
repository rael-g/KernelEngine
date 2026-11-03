const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    const built = ke_build.plugin(b, .{
        .name = "ke_ecs_flecs",
        .root = "src/ecs_flecs.zig",
        .abi = &.{ "abi_ecs_variant", "abi_asset_resolver", "abi_ecs", "abi_ecs_flecs_factory", "abi_math", "abi_result" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .extra_roots = &.{"src/abort_probe.zig"},
        .tests = "Run the ecs_flecs unit + abort-integration tests",
    });

    const probe_exe = b.addExecutable(.{ .name = "ecs_flecs_abort_probe", .root_module = built.extra[0] });
    const options = b.addOptions();
    if (built.extra[0].resolved_target.?.result.os.tag == .windows) {
        const beside = b.addWriteFiles();
        options.addOptionPath("probe_exe_path", beside.addCopyFile(probe_exe.getEmittedBin(), probe_exe.out_filename));
        _ = beside.addCopyFile(probe_exe.getEmittedPdb(), b.fmt("{s}.pdb", .{probe_exe.name}));
    } else {
        options.addOptionPath("probe_exe_path", probe_exe.getEmittedBin());
    }
    const integration = b.createModule(.{
        .root_source_file = b.path("src/abort_integration_test.zig"),
        .target = built.extra[0].resolved_target,
        .optimize = built.extra[0].optimize,
        .link_libc = true,
    });
    integration.addOptions("build_options", options);
    built.test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = integration })).step);
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const flecs_include = b.option([]const u8, "flecs-include", "flecs headers dir") orelse @panic("-Dflecs-include required");
    const flecs_lib = b.option([]const u8, "flecs-lib", "absolute path to the flecs static library") orelse @panic("-Dflecs-lib required");
    for (modules.all(b)) |mod| {
        mod.addIncludePath(.{ .cwd_relative = flecs_include });

        mod.addObjectFile(.{ .cwd_relative = flecs_lib });

        if (mod.resolved_target.?.result.os.tag == .windows) {
            mod.linkSystemLibrary("ws2_32", .{});
            mod.linkSystemLibrary("dbghelp", .{});
        }

        mod.addCMacro("flecs_STATIC", "");
    }
}
