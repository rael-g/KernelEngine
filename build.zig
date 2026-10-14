const std = @import("std");

const docir = @import("docir");

const abi_stamp = @import("scripts/abi_stamp.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const debug = optimize == .Debug;

    const root = b.build_root.path orelse @panic("build.zig must run from the repo root");

    const host_windows = b.graph.host.result.os.tag == .windows;
    const triplet = switch (target.result.os.tag) {
        .windows => "x64-windows-zig",
        else => "x64-linux-zig",
    };
    const host_triplet = if (host_windows) "x64-windows-zig" else "x64-linux-zig";

    const tools_dir = b.pathJoin(&.{ root, "build", "tools" });
    const zig_cache_dir = b.pathJoin(&.{ root, ".zig-cache" });

    const vcpkg_tool_version = "2026-07-13";
    const vcpkg_dir_default = b.pathJoin(&.{ tools_dir, b.fmt("vcpkg-{s}", .{vcpkg_tool_version}) });
    const vcpkg_root = b.option([]const u8, "vcpkg-root", "path to the vcpkg checkout") orelse
        b.graph.environ_map.get("VCPKG_ROOT") orelse
        vcpkg_dir_default;
    const vcpkg_exe = b.pathJoin(&.{ vcpkg_root, if (host_windows) "vcpkg.exe" else "vcpkg" });
    const vcpkg_bundle_url = b.fmt("https://github.com/microsoft/vcpkg-tool/releases/download/{s}/vcpkg-standalone-bundle.tar.gz", .{vcpkg_tool_version});
    const vcpkg_bin_asset = if (host_windows) "vcpkg.exe" else "vcpkg-glibc";
    const vcpkg_bin_url = b.fmt("https://github.com/microsoft/vcpkg-tool/releases/download/{s}/{s}", .{ vcpkg_tool_version, vcpkg_bin_asset });
    const vcpkg_name = if (host_windows) "vcpkg.exe" else "vcpkg";
    const vcpkg_archives = b.pathJoin(&.{ root, "build", "vcpkg-archives" });
    const vcpkg_registries = b.pathJoin(&.{ root, "build", "vcpkg-registries" });
    const zig_global_cache_dir = b.pathJoin(&.{ root, "build", "zig-global" });
    const vcpkg_fetch = b.addSystemCommand(&.{
        "sh", "-c",
        b.fmt(
            "mkdir -p '{s}' '{s}' '{s}' && ([ -f '{s}' ] || (cd '{s}' && curl -fsSL -o bundle.tar.gz '{s}' && tar -xzf bundle.tar.gz && curl -fsSL -o '{s}' '{s}' && chmod +x '{s}'))",
            .{ vcpkg_root, vcpkg_archives, vcpkg_registries, vcpkg_exe, vcpkg_root, vcpkg_bundle_url, vcpkg_name, vcpkg_bin_url, vcpkg_name },
        ),
    });

    const vcpkg_installed = if (target.result.os.tag == b.graph.host.result.os.tag)
        b.pathJoin(&.{ root, "build", "vcpkg-installed" })
    else
        b.pathJoin(&.{ root, "build", b.fmt("vcpkg-installed-{s}", .{triplet}) });
    const vcpkg_overlay_triplets = b.pathJoin(&.{ root, "vcpkg-triplets" });
    var vcpkg_install_args: std.ArrayList([]const u8) = .empty;
    vcpkg_install_args.appendSlice(b.allocator, &.{
        vcpkg_exe,
        "install",
        b.fmt("--triplet={s}", .{triplet}),
        b.fmt("--x-manifest-root={s}", .{root}),
        b.fmt("--x-install-root={s}", .{vcpkg_installed}),
        b.fmt("--overlay-triplets={s}", .{vcpkg_overlay_triplets}),
        b.fmt("--host-triplet={s}", .{host_triplet}),
    }) catch @panic("OOM");
    const vcpkg_install = b.addSystemCommand(vcpkg_install_args.items);
    vcpkg_install.setEnvironmentVariable("ZIG_LOCAL_CACHE_DIR", zig_cache_dir);
    vcpkg_install.setEnvironmentVariable("ZIG_GLOBAL_CACHE_DIR", zig_global_cache_dir);
    vcpkg_install.setEnvironmentVariable("VCPKG_DEFAULT_BINARY_CACHE", vcpkg_archives);
    vcpkg_install.setEnvironmentVariable("X_VCPKG_REGISTRIES_CACHE", vcpkg_registries);
    vcpkg_install.step.dependOn(&vcpkg_fetch.step);

    const ports_digest = portsDigest(b, root, &.{ vcpkg_tool_version, @import("builtin").zig_version_string, triplet, host_triplet });
    const ports_stamp = b.pathJoin(&.{ vcpkg_installed, "ke-ports.stamp" });
    const ports_step: *std.Build.Step = if (portsCurrent(b, ports_stamp, ports_digest, b.pathJoin(&.{ vcpkg_installed, triplet, "lib" })))
        b.step("vcpkg-current", "the installed ports match the manifest, the triplets and the toolchain")
    else blk: {
        const write_stamp = b.addSystemCommand(&.{ "sh", "-c", b.fmt("printf '%s' '{s}' > '{s}'", .{ ports_digest, ports_stamp }) });
        write_stamp.step.dependOn(&vcpkg_install.step);
        break :blk &write_stamp.step;
    };

    const vcpkg_include = b.pathJoin(&.{ vcpkg_installed, triplet, "include" });
    const vcpkg_lib_release = b.pathJoin(&.{ vcpkg_installed, triplet, "lib" });
    const vcpkg_lib = if (debug) b.pathJoin(&.{ vcpkg_installed, triplet, "debug", "lib" }) else vcpkg_lib_release;

    const src_c = b.pathJoin(&.{ root, "src/c" });
    const src_zig = b.pathJoin(&.{ root, "src/zig" });
    const kerror_src = b.pathJoin(&.{ src_zig, "common/kerror.zig" });
    const heap_src = b.pathJoin(&.{ src_zig, "common/heap.zig" });
    const component_fields_src = b.pathJoin(&.{ src_zig, "common/component_fields.zig" });
    const handle_src = b.pathJoin(&.{ src_zig, "render/common/handle.zig" });
    const stubs_src = b.pathJoin(&.{ src_zig, "common/stubs.zig" });
    const tomlc99_dir = b.pathJoin(&.{ src_zig, "common/third_party/tomlc99" });
    const absolute_prefix = if (std.fs.path.isAbsolute(b.install_prefix))
        b.install_prefix
    else
        b.pathJoin(&.{ root, b.install_prefix });

    const slang_version = "2025.17.2";
    const slang_url_name = switch (b.graph.host.result.os.tag) {
        .windows => b.fmt("slang-{s}-windows-x86_64", .{slang_version}),
        else => b.fmt("slang-{s}-linux-x86_64", .{slang_version}),
    };
    const slang_dir = b.pathJoin(&.{ tools_dir, slang_url_name });
    const slang_zip = b.pathJoin(&.{ slang_dir, "slang.zip" });
    const slang_url = b.fmt("https://github.com/shader-slang/slang/releases/download/v{s}/{s}.zip", .{ slang_version, slang_url_name });
    const slangc_exe = b.pathJoin(&.{ slang_dir, "bin", if (host_windows) "slangc.exe" else "slangc" });
    const slang_fetch = b.addSystemCommand(&.{
        "sh", "-c",
        b.fmt("mkdir -p '{s}' && ([ -f '{s}' ] || (curl -fsSL -o '{s}' '{s}' && unzip -oq '{s}' -d '{s}'))", .{
            slang_dir, slangc_exe, slang_zip, slang_url, slang_zip, slang_dir,
        }),
    });

    var ctx = Ctx{
        .b = b,
        .root = root,
        .prefix = absolute_prefix,
        .vcpkg_step = ports_step,
        .exe_suffix = if (target.result.os.tag == .windows) ".exe" else "",
        .slangc_exe = slangc_exe,
        .slang_step = &slang_fetch.step,
        .plugins_step = b.step("plugins", "Build every native plugin into the shared prefix"),
        .test_step = b.step("test", "Run every plugin's own Zig tests"),
        .docs_step = b.step("docs", "Write the documentation of the native sources and of kabic"),
    };

    const docir_exe = b.dependency("docir", .{ .target = b.graph.host, .optimize = .ReleaseSafe }).artifact("docir");
    const docir_install = b.addInstallArtifact(docir_exe, .{});
    b.getInstallStep().dependOn(&docir_install.step);
    ctx.docs_step.dependOn(&docir_install.step);
    ctx.docs_step.dependOn(docir.addSourceDocs(b, docir_exe, b.path("src"), .{
        .name = "engine",
        .title = "KernelEngine",
        .pages = true,
        .excluded_dirs = &.{ b.path("src/csharp"), b.path("src/shaders") },
        .excluded_names = &.{ "build.zig", "third_party" },
    }));
    ctx.docs_step.dependOn(docir.addSourceDocs(b, docir_exe, b.path("src/csharp/kabic"), .{
        .name = "kabic",
        .title = "Kabic",
        .pages = true,
    }));

    const common = ctx.member("ke_common", .{ .target = target, .optimize = optimize }, &.{}, .has_tests);

    const logger_simple = ctx.member("ke_logger_simple", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"kerror-src" = kerror_src,
    }, &.{}, .has_tests);

    const ecs_flecs = ctx.member("ke_ecs_flecs", .{
        .target = target,
        .optimize = optimize,
        .@"component-fields-src" = component_fields_src,
        .@"heap-src" = heap_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"flecs-include" = vcpkg_include,
        .@"flecs-lib" = b.pathJoin(&.{ vcpkg_lib, "libflecs_static.a" }),
        .@"kerror-src" = kerror_src,
    }, &.{}, .has_tests);

    const input_default = ctx.member("ke_input_default", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-input-include" = b.pathJoin(&.{ src_c, "input" }),
        .@"kerror-src" = kerror_src,
    }, &.{}, .has_tests);

    const resource_cache_default = ctx.member("ke_resource_cache_default", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-resource-cache-include" = b.pathJoin(&.{ src_c, "resource_cache" }),
        .@"kerror-src" = kerror_src,
    }, &.{}, .has_tests);

    const scheduler_enki = ctx.member("ke_scheduler_enki", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-scheduler-include" = b.pathJoin(&.{ src_c, "scheduler" }),
        .@"enki-include" = b.pathJoin(&.{ vcpkg_include, "enkiTS" }),
        .@"enki-lib" = vcpkg_lib,
        .@"kerror-src" = kerror_src,
    }, &.{}, .has_tests);

    const runtime = ctx.member("ke_runtime", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-scheduler-include" = b.pathJoin(&.{ src_c, "scheduler" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"kerror-src" = kerror_src,
        .@"ke-lib-dir" = b.pathJoin(&.{ ctx.prefix, "lib" }),
    }, &.{&common.step}, .has_tests);

    const framework = ctx.member("ke_framework", .{
        .target = target,
        .optimize = optimize,
        .@"component-fields-src" = component_fields_src,
        .@"handle-src" = handle_src,
        .@"heap-src" = heap_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-framework-include" = b.pathJoin(&.{ src_c, "framework" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-input-include" = b.pathJoin(&.{ src_c, "input" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-asset-include" = b.pathJoin(&.{ src_c, "asset" }),
        .@"ke-text-include" = b.pathJoin(&.{ src_c, "text" }),
        .@"ke-audio-include" = b.pathJoin(&.{ src_c, "audio" }),
        .@"ke-physics-include" = b.pathJoin(&.{ src_c, "physics" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-scheduler-include" = b.pathJoin(&.{ src_c, "scheduler" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"kerror-src" = kerror_src,
        .@"tomlc99-dir" = tomlc99_dir,
        .@"ke-lib-dir" = b.pathJoin(&.{ ctx.prefix, "lib" }),
    }, &.{&common.step}, .has_tests);

    const window_glfw = ctx.member("ke_window_glfw", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-window-include" = b.pathJoin(&.{ src_c, "window" }),
        .@"ke-input-include" = b.pathJoin(&.{ src_c, "input" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"glfw-include" = vcpkg_include,
        .@"glfw-lib" = vcpkg_lib,
        .@"kerror-src" = kerror_src,
    }, &.{}, .has_tests);

    const asset_stb_image = ctx.member("ke_asset_stb_image", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-asset-include" = b.pathJoin(&.{ src_c, "asset" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "asset/stb_image/include" }),
        .@"stb-include" = vcpkg_include,
        .@"kerror-src" = kerror_src,
    }, &.{}, .has_tests);

    const audio_miniaudio = ctx.member("ke_audio_miniaudio", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-audio-include" = b.pathJoin(&.{ src_c, "audio" }),
        .@"ke-resource-cache-include" = b.pathJoin(&.{ src_c, "resource_cache" }),
        .@"ke-resource-cache-default-include" = b.pathJoin(&.{ src_zig, "resource_cache/default/include" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "audio/miniaudio/include" }),
        .@"miniaudio-include" = vcpkg_include,
        .@"ke-resource-cache-lib-dir" = b.pathJoin(&.{ ctx.prefix, "lib" }),
        .@"kerror-src" = kerror_src,
    }, &.{&resource_cache_default.step}, .has_tests);

    const text_stb_truetype = ctx.member("ke_text_stb_truetype", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-text-include" = b.pathJoin(&.{ src_c, "text" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "text/stb_truetype/include" }),
        .@"stb-include" = vcpkg_include,
        .@"kerror-src" = kerror_src,
    }, &.{}, .has_tests);

    const physics_box2d = ctx.member("ke_physics_2d_box2d", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-physics-include" = b.pathJoin(&.{ src_c, "physics" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"box2d-include" = vcpkg_include,
        .@"box2d-lib" = b.pathJoin(&.{ vcpkg_lib, if (debug) "libbox2dd.a" else "libbox2d.a" }),
        .@"kerror-src" = kerror_src,
    }, &.{}, .has_tests);

    const is_windows = target.result.os.tag == .windows;
    const assimp_libs = b.fmt("{s}|{s}|{s}|{s}|{s}|{s}", .{
        b.pathJoin(&.{ vcpkg_lib, if (debug) "libassimpd.a" else "libassimp.a" }),
        b.pathJoin(&.{ vcpkg_lib, "libpolyclipping.a" }),
        b.pathJoin(&.{ vcpkg_lib, "libpoly2tri.a" }),
        b.pathJoin(&.{ vcpkg_lib, "libpugixml.a" }),
        b.pathJoin(&.{ vcpkg_lib_release, if (is_windows) "libzs.a" else "libz.a" }),
        b.pathJoin(&.{ vcpkg_lib, if (is_windows)
            (if (debug) "libminizipsd.a" else "libminizips.a")
        else
            "libminizip.a" }),
    });
    const asset_assimp = ctx.member("ke_asset_assimp", .{
        .target = target,
        .optimize = optimize,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-asset-include" = b.pathJoin(&.{ src_c, "asset" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-scheduler-include" = b.pathJoin(&.{ src_c, "scheduler" }),
        .@"assimp-include" = vcpkg_include,
        .@"assimp-libs" = assimp_libs,
        .@"stb-include" = vcpkg_include,
        .@"kerror-src" = kerror_src,
    }, &.{}, .has_tests);

    const configuration = ctx.member("ke_configuration", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-config-include" = b.pathJoin(&.{ src_c, "configuration" }),
        .@"ke-lib-dir" = b.pathJoin(&.{ ctx.prefix, "lib" }),
    }, &.{&common.step}, .has_tests);

    const configuration_toml = ctx.member("ke_configuration_toml", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-config-include" = b.pathJoin(&.{ src_c, "configuration" }),
        .@"ke-lib-dir" = b.pathJoin(&.{ ctx.prefix, "lib" }),
        .@"tomlc99-dir" = tomlc99_dir,
    }, &.{&common.step}, .has_tests);

    const wgpu_version = "v24.0.3.1";
    const wgpu_url_name = switch (target.result.os.tag) {
        .windows => "wgpu-windows-x86_64-msvc-release",
        else => "wgpu-linux-x86_64-release",
    };
    const wgpu_dir = b.pathJoin(&.{ tools_dir, wgpu_url_name });
    const wgpu_zip = b.pathJoin(&.{ wgpu_dir, "wgpu.zip" });
    const wgpu_url = b.fmt("https://github.com/gfx-rs/wgpu-native/releases/download/{s}/{s}.zip", .{ wgpu_version, wgpu_url_name });
    const wgpu_native_filename = switch (target.result.os.tag) {
        .windows => "wgpu_native.dll",
        else => "libwgpu_native.so",
    };
    const wgpu_marker = b.pathJoin(&.{ wgpu_dir, "lib", wgpu_native_filename });
    const wgpu_fetch = b.addSystemCommand(&.{
        "sh", "-c",
        b.fmt("mkdir -p '{s}' && ([ -f '{s}' ] || (curl -fsSL -o '{s}' '{s}' && unzip -oq '{s}' -d '{s}'))", .{
            wgpu_dir, wgpu_marker, wgpu_zip, wgpu_url, wgpu_zip, wgpu_dir,
        }),
    });

    const wgpu_include = b.pathJoin(&.{ wgpu_dir, "include" });
    const wgpu_lib_dir = b.pathJoin(&.{ wgpu_dir, "lib" });
    const gpu_device_webgpu = ctx.member("ke_gpu_device_webgpu", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-lib-dir" = b.pathJoin(&.{ ctx.prefix, "lib" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-window-include" = b.pathJoin(&.{ src_c, "window" }),
        .@"ke-scheduler-include" = b.pathJoin(&.{ src_c, "scheduler" }),
        .@"wgpu-include" = wgpu_include,
        .@"wgpu-lib" = wgpu_lib_dir,
    }, &.{ &common.step, &wgpu_fetch.step }, .has_tests);

    const wgpu_copy = b.addSystemCommand(&.{
        "cp",                                                 "-f",
        b.pathJoin(&.{ wgpu_lib_dir, wgpu_native_filename }), b.pathJoin(&.{ ctx.prefix, "lib", wgpu_native_filename }),
    });
    wgpu_copy.step.dependOn(&gpu_device_webgpu.step);

    const lib_dir = b.pathJoin(&.{ ctx.prefix, "lib" });

    const view_space = ctx.member("ke_view_space", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-view-include" = b.pathJoin(&.{ src_c, "view" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "view/space/include" }),
        .@"ke-lib-dir" = lib_dir,
        .@"kerror-src" = kerror_src,
    }, &.{ &common.step }, .has_tests);

    const render_camera = ctx.member("ke_render_camera", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-view-include" = b.pathJoin(&.{ src_c, "view" }),
        .@"kerror-src" = kerror_src,
    }, &.{&common.step}, .has_tests);

    const gpu_render_target_texture = ctx.member("ke_gpu_render_target_texture", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"kerror-src" = kerror_src,
        .@"stubs-src" = stubs_src,
    }, &.{&common.step}, .has_tests);

    const renderdoc_version = "1.46";
    const renderdoc_dir = b.pathJoin(&.{ tools_dir, b.fmt("renderdoc-{s}", .{renderdoc_version}) });
    const renderdoc_include = b.pathJoin(&.{ renderdoc_dir, if (host_windows) b.fmt("RenderDoc_{s}_64", .{renderdoc_version}) else "include" });
    const renderdoc_marker = if (host_windows)
        b.pathJoin(&.{ renderdoc_include, "renderdoc_app.h" })
    else
        b.pathJoin(&.{ renderdoc_dir, "share/vulkan/implicit_layer.d/renderdoc_capture.json" });
    const renderdoc_fetch = b.addSystemCommand(&.{
        "sh", "-c",
        if (host_windows)
            b.fmt("mkdir -p '{0s}' && ([ -f '{1s}' ] || (curl -fsSL -o '{0s}/renderdoc.zip' 'https://renderdoc.org/stable/{2s}/RenderDoc_{2s}_64.zip' && echo '9ca4d09ecaba2cc791168660d6fc2a7e3d70fe67146e87ec05c5f8dea70772f7  {0s}/renderdoc.zip' | sha256sum -c - && unzip -oq '{0s}/renderdoc.zip' -d '{0s}'))", .{
                renderdoc_dir, renderdoc_marker, renderdoc_version,
            })
        else
            b.fmt("mkdir -p '{0s}/share/vulkan/implicit_layer.d' && ([ -f '{1s}' ] || (curl -fsSL -o '{0s}/renderdoc.tar.gz' 'https://renderdoc.org/stable/{2s}/renderdoc_{2s}.tar.gz' && echo '6fedf15eab1288d9a81889ba8a4452dca53f5c10de8162be32a0f8972f62dc09  {0s}/renderdoc.tar.gz' | sha256sum -c - && tar -xzf '{0s}/renderdoc.tar.gz' -C '{0s}' --strip-components=1 && sed 's|\"library_path\": *\"[^\"]*\"|\"library_path\": \"../../../lib/librenderdoc.so\"|' '{0s}/etc/vulkan/implicit_layer.d/renderdoc_capture.json' > '{1s}'))", .{
                renderdoc_dir, renderdoc_marker, renderdoc_version,
            }),
    });

    const gpu_render_target_renderdoc = ctx.member("ke_gpu_render_target_renderdoc", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"kerror-src" = kerror_src,
        .@"renderdoc-include" = renderdoc_include,
    }, &.{ &common.step, &renderdoc_fetch.step }, .has_tests);

    const shaders_out = b.pathJoin(&.{ ctx.prefix, "bin", "shaders" });
    const shader_lib_dir = b.pathJoin(&.{ root, "src/shaders" });

    const tonemap_vs = ctx.shader("tonemap", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/tonemap/shaders/tonemap.slang" }), shaders_out, &.{}, null);
    const tonemap_fs = ctx.shader("tonemap", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/tonemap/shaders/tonemap.slang" }), shaders_out, &.{}, null);
    const tonemap = ctx.member("ke_render_tonemap", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "render/tonemap/include" }),
        .@"ke-lib-dir" = lib_dir,
    }, &.{ &common.step, &tonemap_vs.step, &tonemap_fs.step }, .has_tests);

    const physics_body2d = ctx.member("ke_physics_body2d", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-physics-include" = b.pathJoin(&.{ src_c, "physics" }),
        .@"ke-framework-include" = b.pathJoin(&.{ src_c, "framework" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "physics/body2d/include" }),
        .@"ke-lib-dir" = lib_dir,
    }, &.{ &common.step }, .has_tests);

    const audio_module = ctx.member("ke_audio_module", .{
        .target = target,
        .optimize = optimize,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-audio-include" = b.pathJoin(&.{ src_c, "audio" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-framework-include" = b.pathJoin(&.{ src_c, "framework" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "audio/module/include" }),
        .@"ke-lib-dir" = lib_dir,
    }, &.{ &common.step }, .no_tests);

    const skybox_vs = ctx.shader("skybox", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/skybox/shaders/skybox.slang" }), shaders_out, &.{}, null);
    const skybox_fs = ctx.shader("skybox", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/skybox/shaders/skybox.slang" }), shaders_out, &.{}, null);
    const skybox = ctx.member("ke_render_skybox", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-view-include" = b.pathJoin(&.{ src_c, "view" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "render/skybox/include" }),
        .@"ke-lib-dir" = lib_dir,
    }, &.{ &common.step, &skybox_vs.step, &skybox_fs.step }, .has_tests);

    const ui_vs = ctx.shader("ui", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/ui/shaders/ui.slang" }), shaders_out, &.{}, null);
    const ui_fs = ctx.shader("ui", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/ui/shaders/ui.slang" }), shaders_out, &.{}, null);
    const ui = ctx.member("ke_render_ui", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"handle-src" = handle_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-text-include" = b.pathJoin(&.{ src_c, "text" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "render/ui/include" }),
        .@"ke-lib-dir" = lib_dir,
    }, &.{ &common.step, &ui_vs.step, &ui_fs.step }, .has_tests);

    const shadow_vs = ctx.shader("shadow", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/shadow/shaders/shadow.slang" }), shaders_out, &.{}, null);
    const shadow_fs = ctx.shader("shadow", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/shadow/shaders/shadow.slang" }), shaders_out, &.{}, null);
    const shadow = ctx.member("ke_render_shadow", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-view-include" = b.pathJoin(&.{ src_c, "view" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "render/shadow/include" }),
        .@"ke-lib-dir" = lib_dir,
    }, &.{ &common.step, &shadow_vs.step, &shadow_fs.step }, .has_tests);

    const cluster_cs = ctx.shader("cluster_cull", "compute", "cs_main", b.pathJoin(&.{ src_zig, "render/cluster/shaders/cluster_cull.slang" }), shaders_out, &.{}, null);
    const cluster = ctx.member("ke_render_cluster", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-view-include" = b.pathJoin(&.{ src_c, "view" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "render/cluster/include" }),
        .@"ke-lib-dir" = lib_dir,
    }, &.{ &common.step, &cluster_cs.step }, .has_tests);

    const dl_includes = [_][]const u8{ shader_lib_dir, b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders" }) };
    const deferred_lighting_vs = ctx.shader("deferred_lighting", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders/deferred_lighting.slang" }), shaders_out, &dl_includes, null);
    const deferred_lighting_fs = ctx.shader("deferred_lighting", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders/deferred_lighting.slang" }), shaders_out, &dl_includes, null);
    const deferred_lighting = ctx.member("ke_render_deferred_lighting", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-view-include" = b.pathJoin(&.{ src_c, "view" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "render/deferred_lighting/include" }),
        .@"ke-lib-dir" = lib_dir,
    }, &.{ &common.step, &deferred_lighting_vs.step, &deferred_lighting_fs.step }, .has_tests);

    const materials_dirs = [_][]const u8{
        b.pathJoin(&.{ shader_lib_dir, "materials" }),
        b.pathJoin(&.{ root, "examples/csharp/03_pbr_directional/materials" }),
    };

    const gbuffer_includes = [_][]const u8{ shader_lib_dir, b.pathJoin(&.{ src_zig, "render/gbuffer/shaders" }) };
    const gbuffer_material_shaders = ctx.materialShaders(
        "gbuffer",
        b.pathJoin(&.{ src_zig, "render/gbuffer/shaders/gbuffer_material.slang.in" }),
        &gbuffer_includes,
        shaders_out,
        &materials_dirs,
    );
    const gbuffer = ctx.member("ke_render_gbuffer", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-view-include" = b.pathJoin(&.{ src_c, "view" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "render/gbuffer/include" }),
        .@"ke-lib-dir" = lib_dir,
    }, &.{ &common.step }, .has_tests);
    for (gbuffer_material_shaders) |s| gbuffer.step.dependOn(&s.step);

    const forward_includes = [_][]const u8{ shader_lib_dir, b.pathJoin(&.{ src_zig, "render/forward/shaders" }) };
    const forward_material_shaders = ctx.materialShaders(
        "forward",
        b.pathJoin(&.{ src_zig, "render/forward/shaders/forward_material.slang.in" }),
        &forward_includes,
        shaders_out,
        &materials_dirs,
    );
    const forward = ctx.member("ke_render_forward", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-view-include" = b.pathJoin(&.{ src_c, "view" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "render/forward/include" }),
        .@"ke-lib-dir" = lib_dir,
    }, &.{ &common.step }, .has_tests);
    for (forward_material_shaders) |s| forward.step.dependOn(&s.step);

    const service_gen_dir = b.pathJoin(&.{ ctx.prefix, "gen", "render_service" });
    const magenta_slang = b.pathJoin(&.{ src_zig, "render/service/shaders/magenta.slang" });
    const magenta_vs = ctx.shader("magenta", "vertex", "vs_main", magenta_slang, service_gen_dir, &.{}, null);
    const magenta_fs = ctx.shader("magenta", "fragment", "fs_main", magenta_slang, service_gen_dir, &.{}, null);
    const magenta_vs_wgsl = b.pathJoin(&.{ service_gen_dir, "magenta.vs.wgsl" });
    const magenta_fs_wgsl = b.pathJoin(&.{ service_gen_dir, "magenta.fs.wgsl" });

    const render_service = ctx.member("ke_render_service", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"handle-src" = handle_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-framework-include" = b.pathJoin(&.{ src_c, "framework" }),
        .@"ke-resource-cache-include" = b.pathJoin(&.{ src_c, "resource_cache" }),
        .@"ke-resource-cache-default-include" = b.pathJoin(&.{ src_zig, "resource_cache/default/include" }),
        .@"ke-text-include" = b.pathJoin(&.{ src_c, "text" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "render/service/include" }),
        .@"ke-lib-dir" = lib_dir,
        .@"magenta-vs-wgsl" = magenta_vs_wgsl,
        .@"magenta-fs-wgsl" = magenta_fs_wgsl,
    }, &.{
        &common.step,     &resource_cache_default.step,
        &magenta_vs.step, &magenta_fs.step,
    }, .has_tests);

    const render_module = ctx.member("ke_render_module", .{
        .target = target,
        .optimize = optimize,
        .@"heap-src" = heap_src,
        .@"stubs-src" = stubs_src,
        .@"ke-math-include" = b.pathJoin(&.{ src_c, "math" }),
        .@"ke-common-include" = b.pathJoin(&.{ src_zig, "common/include" }),
        .@"ke-ecs-include" = b.pathJoin(&.{ src_c, "ecs" }),
        .@"ke-runtime-include" = b.pathJoin(&.{ src_c, "runtime" }),
        .@"ke-spatial-include" = b.pathJoin(&.{ src_c, "spatial" }),
        .@"ke-render-include" = b.pathJoin(&.{ src_c, "render" }),
        .@"ke-view-include" = b.pathJoin(&.{ src_c, "view" }),
        .@"ke-framework-include" = b.pathJoin(&.{ src_c, "framework" }),
        .@"ke-text-include" = b.pathJoin(&.{ src_c, "text" }),
        .@"ke-logger-include" = b.pathJoin(&.{ src_c, "logger" }),
        .@"ke-asset-include" = b.pathJoin(&.{ src_c, "asset" }),
        .@"ke-service-include" = b.pathJoin(&.{ src_zig, "render/service/include" }),
        .@"ke-self-include" = b.pathJoin(&.{ src_zig, "render/module/include" }),
        .@"ke-view-space-include" = b.pathJoin(&.{ src_zig, "view/space/include" }),
        .@"ke-camera-include" = b.pathJoin(&.{ src_zig, "render/camera/include" }),
        .@"ke-tonemap-include" = b.pathJoin(&.{ src_zig, "render/tonemap/include" }),
        .@"ke-skybox-include" = b.pathJoin(&.{ src_zig, "render/skybox/include" }),
        .@"ke-ui-include" = b.pathJoin(&.{ src_zig, "render/ui/include" }),
        .@"ke-gbuffer-include" = b.pathJoin(&.{ src_zig, "render/gbuffer/include" }),
        .@"ke-shadow-include" = b.pathJoin(&.{ src_zig, "render/shadow/include" }),
        .@"ke-cluster-include" = b.pathJoin(&.{ src_zig, "render/cluster/include" }),
        .@"ke-deferred-lighting-include" = b.pathJoin(&.{ src_zig, "render/deferred_lighting/include" }),
        .@"ke-forward-include" = b.pathJoin(&.{ src_zig, "render/forward/include" }),
        .@"ke-lib-dir" = lib_dir,
        .@"kerror-src" = kerror_src,
    }, &.{
        &common.step,            &render_service.step, &view_space.step,
        &tonemap.step,           &skybox.step,  &ui.step,
        &gbuffer.step,           &shadow.step,  &cluster.step,
        &deferred_lighting.step, &forward.step, &render_camera.step,
    }, .has_tests);

    const all_plugins = [_]*std.Build.Step.InstallArtifact{
        render_module,     common,                 logger_simple,      ecs_flecs,
        input_default,     resource_cache_default, scheduler_enki,     runtime,
        framework,         window_glfw,            asset_stb_image,    audio_miniaudio,
        text_stb_truetype, physics_box2d,          physics_body2d,     asset_assimp,
        configuration,     audio_module,           configuration_toml, tonemap,
        skybox,            ui,                     shadow,             cluster,
        deferred_lighting, gpu_device_webgpu,      gbuffer,            forward,
        render_service,    render_camera,
    };
    for (all_plugins) |p| b.getInstallStep().dependOn(&p.step);
    b.getInstallStep().dependOn(&wgpu_copy.step);
    b.getInstallStep().dependOn(ctx.plugins_step);
    ctx.plugins_step.dependOn(&wgpu_copy.step);

    var stamp_threaded: std.Io.Threaded = .init(b.allocator, .{});
    defer stamp_threaded.deinit();
    const stamp_text = abi_stamp.compute(b.allocator, stamp_threaded.io(), root) catch |err|
        std.debug.panic("cannot stamp the contract headers: {s}", .{@errorName(err)});
    const stamp_install = b.addInstallFileWithDir(b.addWriteFiles().add("abi.stamp", stamp_text), .prefix, "abi.stamp");
    for (all_plugins) |p| stamp_install.step.dependOn(&p.step);
    stamp_install.step.dependOn(&wgpu_copy.step);
    b.getInstallStep().dependOn(&stamp_install.step);
    ctx.plugins_step.dependOn(&stamp_install.step);

    if (target.result.os.tag == .windows) {
        const copy_dlls_to_bin = b.addSystemCommand(&.{
            "sh",                                                                                 "-c",
            b.fmt("cp -f '{s}'/*.dll '{s}'/", .{ lib_dir, b.pathJoin(&.{ ctx.prefix, "bin" }) }),
        });
        for (all_plugins) |p| copy_dlls_to_bin.step.dependOn(&p.step);
        copy_dlls_to_bin.step.dependOn(&wgpu_copy.step);
        copy_dlls_to_bin.setName("copy plugin DLLs into bin/");
        b.getInstallStep().dependOn(&copy_dlls_to_bin.step);
    }

    const demo01 = ctx.example("c_demo_01", .{
        .target = target,
        .optimize = optimize,
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "logger" }),
            b.pathJoin(&.{ src_zig, "logger/simple/include" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
        }),
        .@"libs" = b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_logger_simple") }),
    }, &.{&logger_simple.step});

    const demo_step = b.step("demo01", "Build examples/c/01_minimal_log");
    demo_step.dependOn(&demo01.step);

    const examples_gen = b.pathJoin(&.{ ctx.prefix, "gen", "examples" });

    const demo05 = ctx.example("c_demo_05", .{
        .target = target,
        .optimize = optimize,
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        }),
        .@"libs" = b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
    }, &.{&gpu_device_webgpu.step});

    const compile_slang_dir = b.pathJoin(&.{ root, "build", "tools", "compile_slang" });
    const compile_slang_dll = b.pathJoin(&.{ compile_slang_dir, "compile_slang.dll" });
    const compile_slang_build = b.addSystemCommand(&.{ "dotnet", "build", b.pathJoin(&.{ root, "scripts/compile_slang.cs" }), "-o", compile_slang_dir, "--nologo", "-v", "q" });
    compile_slang_build.expectExitCode(0);
    compile_slang_build.has_side_effects = true;

    const demo06 = ctx.example("c_demo_06", .{
        .target = target,
        .optimize = optimize,
        .@"shader-name" = "triangle",
        .@"compile-slang" = compile_slang_dll,
        .@"slangc" = ctx.slangc_exe,
        .@"shader-out-dir" = b.pathJoin(&.{ examples_gen, "06_triangle" }),
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        }),
        .@"libs" = joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        }),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, ctx.slang_step, &compile_slang_build.step });

    const demo15 = ctx.example("c_demo_15", .{
        .target = target,
        .optimize = optimize,
        .@"shader-name" = "triangle",
        .@"compile-slang" = compile_slang_dll,
        .@"slangc" = ctx.slangc_exe,
        .@"shader-out-dir" = b.pathJoin(&.{ examples_gen, "15_offscreen_capture" }),
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "render/texture_target/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
            vcpkg_include,
        }),
        .@"libs" = joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_render_target_texture") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        }),
    }, &.{ &common.step, &gpu_render_target_texture.step, &gpu_device_webgpu.step, ctx.slang_step, &compile_slang_build.step });

    const demo07 = ctx.example("c_demo_07", .{
        .target = target,
        .optimize = optimize,
        .@"shader-name" = "rotate",
        .@"compile-slang" = compile_slang_dll,
        .@"slangc" = ctx.slangc_exe,
        .@"shader-out-dir" = b.pathJoin(&.{ examples_gen, "07_uniform" }),
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        }),
        .@"libs" = joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        }),
        .@"link-m" = true,
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, ctx.slang_step, &compile_slang_build.step });

    const demo08 = ctx.example("c_demo_08", .{
        .target = target,
        .optimize = optimize,
        .@"shader-name" = "mesh",
        .@"compile-slang" = compile_slang_dll,
        .@"slangc" = ctx.slangc_exe,
        .@"shader-out-dir" = b.pathJoin(&.{ examples_gen, "08_vertex_buffer" }),
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        }),
        .@"libs" = joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        }),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, ctx.slang_step, &compile_slang_build.step });

    const demo09 = ctx.example("c_demo_09", .{
        .target = target,
        .optimize = optimize,
        .@"shader-name" = "tex",
        .@"compile-slang" = compile_slang_dll,
        .@"slangc" = ctx.slangc_exe,
        .@"shader-out-dir" = b.pathJoin(&.{ examples_gen, "09_texture" }),
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        }),
        .@"libs" = joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        }),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, ctx.slang_step, &compile_slang_build.step });

    const demo10 = ctx.example("c_demo_10", .{
        .target = target,
        .optimize = optimize,
        .@"shader-name" = "depth",
        .@"compile-slang" = compile_slang_dll,
        .@"slangc" = ctx.slangc_exe,
        .@"shader-out-dir" = b.pathJoin(&.{ examples_gen, "10_depth" }),
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        }),
        .@"libs" = joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        }),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, ctx.slang_step, &compile_slang_build.step });

    const demo12 = ctx.example("c_demo_12", .{
        .target = target,
        .optimize = optimize,
        .@"compile-slang" = compile_slang_dll,
        .@"slangc" = ctx.slangc_exe,
        .@"shader-out-dir" = b.pathJoin(&.{ examples_gen, "12_render_service" }),
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
            b.pathJoin(&.{ src_zig, "render/service/include" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
        }),
        .@"libs" = joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_service") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_module") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
        }),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, &render_service.step, &render_module.step, &ecs_flecs.step, ctx.slang_step, &compile_slang_build.step });

    const demo13 = ctx.example("c_demo_13", .{
        .target = target,
        .optimize = optimize,
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "spatial" }),
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_c, "scheduler" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
            b.pathJoin(&.{ src_zig, "render/service/include" }),
            b.pathJoin(&.{ src_zig, "render/module/include" }),
            b.pathJoin(&.{ src_zig, "render/shadow/include" }),
            b.pathJoin(&.{ src_zig, "render/ui/include" }),
            b.pathJoin(&.{ src_c, "text" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
            b.pathJoin(&.{ src_zig, "scheduler/enki/include" }),
            b.pathJoin(&.{ src_c, "runtime" }),
            b.pathJoin(&.{ src_zig, "runtime/include" }),
            b.pathJoin(&.{ src_c, "asset" }),
            b.pathJoin(&.{ src_c, "framework" }),
            b.pathJoin(&.{ src_zig, "framework/include" }),
        }),
        .@"libs" = joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_service") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_module") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
        }),
    }, &.{
        &common.step,    &window_glfw.step,    &gpu_device_webgpu.step, &render_service.step, &render_module.step,
        &ecs_flecs.step, &scheduler_enki.step, &runtime.step,
    });

    const demo14 = ctx.example("c_demo_14", .{
        .target = target,
        .optimize = optimize,
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "spatial" }),
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_c, "scheduler" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_zig, "render/service/include" }),
            b.pathJoin(&.{ src_zig, "render/module/include" }),
            b.pathJoin(&.{ src_zig, "render/shadow/include" }),
            b.pathJoin(&.{ src_zig, "render/ui/include" }),
            b.pathJoin(&.{ src_c, "text" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
            b.pathJoin(&.{ src_zig, "scheduler/enki/include" }),
            b.pathJoin(&.{ src_c, "runtime" }),
            b.pathJoin(&.{ src_zig, "runtime/include" }),
            b.pathJoin(&.{ src_c, "asset" }),
            b.pathJoin(&.{ src_c, "framework" }),
            b.pathJoin(&.{ src_zig, "framework/include" }),
        }),
        .@"libs" = joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_service") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_module") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
        }),
        .@"link-m" = true,
    }, &.{
        &common.step,    &window_glfw.step,    &gpu_device_webgpu.step, &render_service.step, &render_module.step,
        &ecs_flecs.step, &scheduler_enki.step, &runtime.step,
    });

    const demo16 = ctx.example("c_demo_16", .{
        .target = target,
        .optimize = optimize,
        .@"include-dirs" = joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "spatial" }),
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_c, "scheduler" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
            b.pathJoin(&.{ src_zig, "render/texture_target/include" }),
            b.pathJoin(&.{ src_zig, "render/renderdoc_target/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_zig, "render/service/include" }),
            b.pathJoin(&.{ src_zig, "render/module/include" }),
            b.pathJoin(&.{ src_zig, "render/shadow/include" }),
            b.pathJoin(&.{ src_zig, "render/ui/include" }),
            b.pathJoin(&.{ src_c, "text" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
            b.pathJoin(&.{ src_zig, "scheduler/enki/include" }),
            b.pathJoin(&.{ src_c, "runtime" }),
            b.pathJoin(&.{ src_zig, "runtime/include" }),
            b.pathJoin(&.{ src_c, "asset" }),
            b.pathJoin(&.{ src_c, "framework" }),
            b.pathJoin(&.{ src_zig, "framework/include" }),
            vcpkg_include,
        }),
        .@"libs" = joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_render_target_texture") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_render_target_renderdoc") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_service") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_module") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
        }),
        .@"link-m" = true,
    }, &.{
        &common.step,    &gpu_render_target_texture.step, &gpu_render_target_renderdoc.step, &gpu_device_webgpu.step, &render_service.step, &render_module.step,
        &ecs_flecs.step, &scheduler_enki.step, &runtime.step,
    });

    const all_examples = [_]*std.Build.Step.InstallArtifact{
        demo01, demo05, demo06, demo07, demo08, demo09, demo10, demo12, demo13, demo14, demo15, demo16,
    };
    for (all_examples) |e| b.getInstallStep().dependOn(&e.step);
}

const Tests = enum { has_tests, no_tests };

const Ctx = struct {
    b: *std.Build,
    root: []const u8,
    prefix: []const u8,
    vcpkg_step: *std.Build.Step,
    slangc_exe: []const u8,
    slang_step: *std.Build.Step,
    plugins_step: *std.Build.Step,
    test_step: *std.Build.Step,
    docs_step: *std.Build.Step,
    exe_suffix: []const u8,
    dotnet_tail: ?*std.Build.Step = null,

    fn serializeDotnet(ctx: *Ctx, step: *std.Build.Step) void {
        if (ctx.dotnet_tail) |tail| step.dependOn(tail);
        ctx.dotnet_tail = step;
    }

    fn addSlangInputs(ctx: *Ctx, run: *std.Build.Step.Run, dir_path: []const u8) void {
        const b = ctx.b;
        var threaded: std.Io.Threaded = .init(b.allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();
        var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return;
        defer dir.close(io);
        var walker = dir.walk(b.allocator) catch @panic("OOM");
        defer walker.deinit();
        while (walker.next(io) catch null) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".slang")) continue;
            run.addFileInput(.{ .cwd_relative = b.pathJoin(&.{ dir_path, entry.path }) });
        }
    }

    /// Compiles one Slang entry point to WGSL via scripts/compile_slang.cs.
    /// Every render pass loads its shaders at runtime by logical name via
    /// ke_render_service::load_shader, so the output always lands in the one
    /// shared runtime shaders directory, never embedded in a plugin's own .so
    /// (render/service's own embedded fallback shader is the one exception —
    /// handled separately, since @embedFile needs the file before that
    /// module's own `zig build` even starts).
    fn shader(ctx: *Ctx, name: []const u8, stage: []const u8, entry: []const u8, input: []const u8, out_dir: []const u8, includes: []const []const u8, after: ?*std.Build.Step) *std.Build.Step.InstallFile {
        const b = ctx.b;
        const suffix = if (std.mem.eql(u8, stage, "vertex"))
            "vs"
        else if (std.mem.eql(u8, stage, "fragment"))
            "fs"
        else
            "cs";
        const file_name = b.fmt("{s}.{s}.wgsl", .{ name, suffix });
        const run = b.addSystemCommand(&.{ ctx.slangc_exe, "-target", "wgsl", "-entry", entry, "-stage", stage });
        run.step.dependOn(ctx.slang_step);
        if (after) |a| run.step.dependOn(a);
        for (includes) |inc| run.addArgs(&.{ "-I", inc });
        run.addFileArg(.{ .cwd_relative = input });
        run.addArg("-o");
        const compiled = run.addOutputFileArg(file_name);
        ctx.addSlangInputs(run, std.fs.path.dirname(input) orelse ".");
        for (includes) |inc| ctx.addSlangInputs(run, inc);
        run.setName(b.fmt("compile {s}.{s}.wgsl", .{ name, suffix }));

        if (!std.mem.startsWith(u8, out_dir, ctx.prefix)) @panic("shader output directory is outside the install prefix");
        const relative = std.mem.trimStart(u8, out_dir[ctx.prefix.len..], "/\\");
        return b.addInstallFileWithDir(compiled, .{ .custom = relative }, file_name);
    }

    /// Compiles every authored material × `pass`: glob every materials
    /// directory (synchronously, during graph construction), generate a wrapper
    /// binding each material into the pass's entry points, then compile the
    /// wrapper like any other pass shader. The
    /// wrapper `import`s the material by module name, so every materials dir
    /// must be on the compile include path alongside the pass's own.
    fn materialShaders(
        ctx: *Ctx,
        pass: []const u8,
        template: []const u8,
        includes: []const []const u8,
        out_dir: []const u8,
        materials_dirs: []const []const u8,
    ) []const *std.Build.Step.InstallFile {
        const b = ctx.b;
        var steps: std.ArrayList(*std.Build.Step.InstallFile) = .empty;
        const gen_dir = b.pathJoin(&.{ ctx.prefix, "gen", pass });

        var wrapper_includes: std.ArrayList([]const u8) = .empty;
        wrapper_includes.appendSlice(b.allocator, includes) catch @panic("OOM");
        wrapper_includes.appendSlice(b.allocator, materials_dirs) catch @panic("OOM");

        var threaded: std.Io.Threaded = .init(b.allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();

        for (materials_dirs) |mdir| {
            var dir = std.Io.Dir.openDirAbsolute(io, mdir, .{ .iterate = true }) catch continue;
            defer dir.close(io);
            var it = dir.iterate();
            while (it.next(io) catch null) |entry| {
                if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".slang")) continue;
                const material_name = entry.name[0 .. entry.name.len - ".slang".len];
                const material_path = b.pathJoin(&.{ mdir, entry.name });
                const combined_name = b.fmt("{s}.{s}", .{ material_name, pass });
                const wrapper = b.pathJoin(&.{ gen_dir, b.fmt("{s}.slang", .{combined_name}) });

                const gen_wrapper = b.addSystemCommand(&.{
                    "dotnet",     "run",         b.pathJoin(&.{ ctx.root, "scripts/generate_material_wrapper.cs" }),
                    "--material", material_path, "--template",
                    template,     "--output",    wrapper,
                });
                gen_wrapper.setName(b.fmt("generate {s} wrapper", .{combined_name}));
                ctx.serializeDotnet(&gen_wrapper.step);

                const vs = ctx.shader(combined_name, "vertex", "vs_main", wrapper, out_dir, wrapper_includes.items, &gen_wrapper.step);
                vs.step.dependOn(&gen_wrapper.step);
                const fs = ctx.shader(combined_name, "fragment", "fs_main", wrapper, out_dir, wrapper_includes.items, &gen_wrapper.step);
                fs.step.dependOn(&gen_wrapper.step);

                steps.append(b.allocator, vs) catch @panic("OOM");
                steps.append(b.allocator, fs) catch @panic("OOM");
            }
        }
        return steps.toOwnedSlice(b.allocator) catch @panic("OOM");
    }

    /// Invokes `zig build --prefix <shared prefix> <extra args>` in `dir`.
    /// Every plugin's own build.zig installs its .so to "lib" under whatever
    /// --prefix it is given, so pointing every invocation at the same prefix
    /// makes them all land in one directory.
    fn member(ctx: *Ctx, name: []const u8, args: anytype, deps: []const *std.Build.Step, tests: Tests) *std.Build.Step.InstallArtifact {
        const b = ctx.b;
        const dependency = b.dependency(name, args);
        const artifact = dependency.artifact(name);
        artifact.step.dependOn(ctx.vcpkg_step);
        for (deps) |d| artifact.step.dependOn(d);
        const install = b.addInstallArtifact(artifact, .{ .dest_dir = .{ .override = .{ .custom = "lib" } } });
        ctx.plugins_step.dependOn(&install.step);

        switch (tests) {
            .no_tests => {},
            .has_tests => {
                const own_tests = &dependency.builder.top_level_steps.get("test").?.step;
                for (own_tests.dependencies.items) |run| run.dependOn(ctx.plugins_step);
                ctx.test_step.dependOn(own_tests);
            },
        }

        return install;
    }

    fn example(ctx: *Ctx, demo_name: []const u8, args: anytype, deps: []const *std.Build.Step) *std.Build.Step.InstallArtifact {
        const b = ctx.b;
        const artifact = b.dependency(demo_name, args).artifact("demo");
        for (artifact.step.dependencies.items) |inner| {
            for (deps) |d| inner.dependOn(d);
        }
        for (deps) |d| artifact.step.dependOn(d);
        artifact.step.dependOn(ctx.vcpkg_step);
        return b.addInstallArtifact(artifact, .{
            .dest_dir = .{ .override = .{ .custom = "bin" } },
            .dest_sub_path = b.fmt("{s}{s}", .{ demo_name, ctx.exe_suffix }),
        });
    }
};

fn portsDigest(b: *std.Build, root: []const u8, parts: []const []const u8) [64]u8 {
    var threaded: std.Io.Threaded = .init(b.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (parts) |part| {
        hasher.update(part);
        hasher.update("\n");
    }
    const cwd = std.Io.Dir.cwd();
    for ([_][]const u8{ "vcpkg.json", "vcpkg-configuration.json" }) |name| {
        const contents = cwd.readFileAlloc(io, b.pathJoin(&.{ root, name }), b.allocator, .limited(1 << 20)) catch "";
        hasher.update(contents);
    }
    var names: std.ArrayList([]const u8) = .empty;
    const triplets_path = b.pathJoin(&.{ root, "vcpkg-triplets" });
    if (std.Io.Dir.openDirAbsolute(io, triplets_path, .{ .iterate = true })) |opened| {
        var dir = opened;
        defer dir.close(io);
        var it = dir.iterate();
        while (it.next(io) catch null) |entry| {
            if (entry.kind == .file) names.append(b.allocator, b.dupe(entry.name)) catch @panic("OOM");
        }
    } else |_| {}
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.lessThan);
    for (names.items) |name| {
        hasher.update(name);
        const contents = cwd.readFileAlloc(io, b.pathJoin(&.{ triplets_path, name }), b.allocator, .limited(1 << 20)) catch "";
        hasher.update(contents);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn portsCurrent(b: *std.Build, stamp_path: []const u8, digest: [64]u8, lib_dir: []const u8) bool {
    var threaded: std.Io.Threaded = .init(b.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();
    const recorded = cwd.readFileAlloc(io, stamp_path, b.allocator, .limited(128)) catch return false;
    if (!std.mem.eql(u8, recorded, &digest)) return false;
    cwd.access(io, lib_dir, .{}) catch return false;
    return true;
}

fn joinPaths(b: *std.Build, paths: []const []const u8) []const u8 {
    return std.mem.join(b.allocator, "|", paths) catch @panic("OOM");
}

/// Every plugin's own build.zig installs a shared library under Zig's default
/// per-target name — "name.dll" on Windows (no "lib" prefix), "libname.so"
/// elsewhere — so any consumer resolving one of these paths by hand (an
/// example's or test suite's `-Dlibs=`) needs to match that convention.
fn libFileName(b: *std.Build, target: std.Build.ResolvedTarget, name: []const u8) []const u8 {
    return if (target.result.os.tag == .windows)
        b.fmt("{s}.dll", .{name})
    else
        b.fmt("lib{s}.so", .{name});
}

/// The GTest suites are linked via a raw `-o <output>` system-compiler
/// invocation (tests/c/kernel/build.zig, tests/integration/cpp/build.zig),
/// not a Zig artifact — so unlike Zig's own addExecutable, nothing appends
/// ".exe" automatically. Without it, cmd.exe and PowerShell both refuse to
/// launch the file at all (only a POSIX-style exec layer like Git Bash's
/// tolerates the missing extension).
fn exeFileName(b: *std.Build, target: std.Build.ResolvedTarget, name: []const u8) []const u8 {
    return if (target.result.os.tag == .windows) b.fmt("{s}.exe", .{name}) else name;
}

