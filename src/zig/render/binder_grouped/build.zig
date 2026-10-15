const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_render = b.option([]const u8, "ke-render-include", "kernel_engine/render include dir") orelse @panic("-Dke-render-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const stubs_src = b.option([]const u8, "stubs-src", "path to the shared Zig stubs.zig") orelse @panic("-Dstubs-src required");
    const shader_files_src = b.option([]const u8, "shader-files-src", "path to the shared Zig shader_files.zig") orelse @panic("-Dshader-files-src required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "dir with ke_common import lib") orelse @panic("-Dke-lib-dir required");
    const material_params_json = b.option([]const u8, "material-params-json", "generated reflection of the material parameter block") orelse @panic("-Dmaterial-params-json required");

    const roots = [_]struct { name: []const u8, tests: bool }{ .{ .name = "lib", .tests = false }, .{ .name = "test", .tests = true } };
    var modules: [roots.len]*std.Build.Module = undefined;
    for (roots, &modules) |r, *m| {
        m.* = b.createModule(.{
            .root_source_file = b.path("src/resource_binder_grouped.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        m.*.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
        m.*.addImport("shader_files", b.createModule(.{ .root_source_file = .{ .cwd_relative = shader_files_src }, .target = target, .optimize = optimize, .link_libc = true }));
        if (r.tests) m.*.addImport("stubs", b.createModule(.{ .root_source_file = .{ .cwd_relative = stubs_src }, .target = target, .optimize = optimize }));
        inline for (.{ ke_common, ke_render }) |inc| m.*.addIncludePath(.{ .cwd_relative = inc });
        m.*.addIncludePath(b.path("include"));
        m.*.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
        m.*.linkSystemLibrary("ke_common", .{});
        m.*.addRPathSpecial("$ORIGIN");
        m.*.addCMacro("KE_RENDER_BINDER_GROUPED_EXPORT", "");
        m.*.addAnonymousImport("material_params.json", .{ .root_source_file = .{ .cwd_relative = material_params_json } });
    }

    const lib = b.addLibrary(.{
        .name = "ke_render_binder_grouped",
        .root_module = modules[0],
        .linkage = .dynamic,
    });
    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const unit_tests = b.addTest(.{ .root_module = modules[1] });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run the grouped resource binder unit tests").dependOn(&run_tests.step);
}
