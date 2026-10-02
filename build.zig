const std = @import("std");

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
    const zig_cache_dir = b.pathJoin(&.{ root, "build", "zig-cache" });

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
    const vcpkg_fetch = b.addSystemCommand(&.{
        "sh", "-c",
        b.fmt(
            "mkdir -p '{s}' && ([ -f '{s}' ] || (cd '{s}' && curl -fsSL -o bundle.tar.gz '{s}' && tar -xzf bundle.tar.gz && curl -fsSL -o '{s}' '{s}' && chmod +x '{s}'))",
            .{ vcpkg_root, vcpkg_exe, vcpkg_root, vcpkg_bundle_url, vcpkg_name, vcpkg_bin_url, vcpkg_name },
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
        .zig_exe = b.graph.zig_exe,
        .prefix = absolute_prefix,
        .cache_dir = zig_cache_dir,
        .release_flag = if (debug) "--release=off" else "--release=fast",
        .vcpkg_step = ports_step,
        .target_arg = if (target.result.os.tag == .windows) "-Dtarget=x86_64-windows-gnu" else "",
        .exe_suffix = if (target.result.os.tag == .windows) ".exe" else "",
        .run_under_wine = target.result.os.tag == .windows and !host_windows,
        .slangc_exe = slangc_exe,
        .slang_step = &slang_fetch.step,
        .plugins_step = b.step("plugins", "Build every native plugin into the shared prefix"),
        .test_step = b.step("test", "Run every plugin's own Zig tests"),
    };

    const common = ctx.plugin("ke_common", "src/zig/common", &.{}, &.{}, .has_tests);

    const logger_simple = ctx.plugin("ke_logger_simple", "src/zig/logger/simple", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{}, .has_tests);

    const ecs_flecs = ctx.plugin("ke_ecs_flecs", "src/zig/ecs/flecs", &.{
        argF(b, "component-fields-src", component_fields_src),
        argF(b, "heap-src", heap_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "flecs-include", vcpkg_include),
        argF(b, "flecs-lib", b.pathJoin(&.{ vcpkg_lib, "libflecs_static.a" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{}, .has_tests);

    const input_default = ctx.plugin("ke_input_default", "src/zig/input/default", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-input-include", b.pathJoin(&.{ src_c, "input" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{}, .has_tests);

    const resource_cache_default = ctx.plugin("ke_resource_cache_default", "src/zig/resource_cache/default", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-resource-cache-include", b.pathJoin(&.{ src_c, "resource_cache" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{}, .has_tests);

    const scheduler_enki = ctx.plugin("ke_scheduler_enki", "src/zig/scheduler/enki", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
        argF(b, "enki-include", b.pathJoin(&.{ vcpkg_include, "enkiTS" })),
        argF(b, "enki-lib", vcpkg_lib),
        argF(b, "kerror-src", kerror_src),
    }, &.{}, .has_tests);

    const runtime = ctx.plugin("ke_runtime", "src/zig/runtime", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "kerror-src", kerror_src),
        argF(b, "ke-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
    }, &.{}, .has_tests);

    const framework = ctx.plugin("ke_framework", "src/zig/framework", &.{
        argF(b, "component-fields-src", component_fields_src),
        argF(b, "handle-src", handle_src),
        argF(b, "heap-src", heap_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-framework-include", b.pathJoin(&.{ src_c, "framework" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-input-include", b.pathJoin(&.{ src_c, "input" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-asset-include", b.pathJoin(&.{ src_c, "asset" })),
        argF(b, "ke-text-include", b.pathJoin(&.{ src_c, "text" })),
        argF(b, "ke-audio-include", b.pathJoin(&.{ src_c, "audio" })),
        argF(b, "ke-physics-include", b.pathJoin(&.{ src_c, "physics" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "kerror-src", kerror_src),
        argF(b, "tomlc99-dir", tomlc99_dir),
        argF(b, "ke-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
    }, &.{}, .has_tests);

    const window_glfw = ctx.plugin("ke_window_glfw", "src/zig/window/glfw", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-window-include", b.pathJoin(&.{ src_c, "window" })),
        argF(b, "ke-input-include", b.pathJoin(&.{ src_c, "input" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "glfw-include", vcpkg_include),
        argF(b, "glfw-lib", vcpkg_lib),
        argF(b, "kerror-src", kerror_src),
    }, &.{}, .has_tests);

    const asset_stb_image = ctx.plugin("ke_asset_stb_image", "src/zig/asset/stb_image", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-asset-include", b.pathJoin(&.{ src_c, "asset" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "asset/stb_image/include" })),
        argF(b, "stb-include", vcpkg_include),
        argF(b, "kerror-src", kerror_src),
    }, &.{}, .has_tests);

    const audio_miniaudio = ctx.plugin("ke_audio_miniaudio", "src/zig/audio/miniaudio", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-audio-include", b.pathJoin(&.{ src_c, "audio" })),
        argF(b, "ke-resource-cache-include", b.pathJoin(&.{ src_c, "resource_cache" })),
        argF(b, "ke-resource-cache-default-include", b.pathJoin(&.{ src_zig, "resource_cache/default/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "audio/miniaudio/include" })),
        argF(b, "miniaudio-include", vcpkg_include),
        argF(b, "ke-resource-cache-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{&resource_cache_default.step}, .has_tests);

    const text_stb_truetype = ctx.plugin("ke_text_stb_truetype", "src/zig/text/stb_truetype", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-text-include", b.pathJoin(&.{ src_c, "text" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "text/stb_truetype/include" })),
        argF(b, "stb-include", vcpkg_include),
        argF(b, "kerror-src", kerror_src),
    }, &.{}, .has_tests);

    const physics_box2d = ctx.plugin("ke_physics_2d_box2d", "src/zig/physics/box2d", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-physics-include", b.pathJoin(&.{ src_c, "physics" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "box2d-include", vcpkg_include),
        argF(b, "box2d-lib", b.pathJoin(&.{ vcpkg_lib, if (debug) "libbox2dd.a" else "libbox2d.a" })),
        argF(b, "kerror-src", kerror_src),
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
    const asset_assimp = ctx.plugin("ke_asset_assimp", "src/zig/asset/assimp", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-asset-include", b.pathJoin(&.{ src_c, "asset" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
        argF(b, "assimp-include", vcpkg_include),
        argF(b, "assimp-libs", assimp_libs),
        argF(b, "stb-include", vcpkg_include),
        argF(b, "kerror-src", kerror_src),
    }, &.{}, .has_tests);

    const configuration = ctx.plugin("ke_configuration", "src/zig/configuration", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-config-include", b.pathJoin(&.{ src_c, "configuration" })),
        argF(b, "ke-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
    }, &.{&common.step}, .has_tests);

    const configuration_toml = ctx.plugin("ke_configuration_toml", "src/zig/configuration/toml", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-config-include", b.pathJoin(&.{ src_c, "configuration" })),
        argF(b, "ke-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
        argF(b, "tomlc99-dir", tomlc99_dir),
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
    const gpu_device_webgpu = ctx.plugin("ke_gpu_device_webgpu", "src/zig/render/webgpu", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-window-include", b.pathJoin(&.{ src_c, "window" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
        argF(b, "wgpu-include", wgpu_include),
        argF(b, "wgpu-lib", wgpu_lib_dir),
    }, &.{ &common.step, &wgpu_fetch.step }, .has_tests);

    const wgpu_copy = b.addSystemCommand(&.{
        "cp",                                                 "-f",
        b.pathJoin(&.{ wgpu_lib_dir, wgpu_native_filename }), b.pathJoin(&.{ ctx.prefix, "lib", wgpu_native_filename }),
    });
    wgpu_copy.step.dependOn(&gpu_device_webgpu.step);

    const lib_dir = b.pathJoin(&.{ ctx.prefix, "lib" });

    const view_space = ctx.plugin("ke_view_space", "src/zig/view/space", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-view-include", b.pathJoin(&.{ src_c, "view" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "view/space/include" })),
        argF(b, "ke-lib-dir", lib_dir),
        argF(b, "kerror-src", kerror_src),
    }, &.{&common.step}, .has_tests);

    const render_camera = ctx.plugin("ke_render_camera", "src/zig/render/camera", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-view-include", b.pathJoin(&.{ src_c, "view" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{&common.step}, .has_tests);

    const shaders_out = b.pathJoin(&.{ ctx.prefix, "bin", "shaders" });
    const shader_lib_dir = b.pathJoin(&.{ root, "src/shaders" });

    const tonemap_vs = ctx.shader("tonemap", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/tonemap/shaders/tonemap.slang" }), shaders_out, &.{}, null);
    const tonemap_fs = ctx.shader("tonemap", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/tonemap/shaders/tonemap.slang" }), shaders_out, &.{}, null);
    const tonemap = ctx.plugin("ke_render_tonemap", "src/zig/render/tonemap", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/tonemap/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &tonemap_vs.step, &tonemap_fs.step }, .has_tests);

    const physics_body2d = ctx.plugin("ke_physics_body2d", "src/zig/physics/body2d", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-physics-include", b.pathJoin(&.{ src_c, "physics" })),
        argF(b, "ke-framework-include", b.pathJoin(&.{ src_c, "framework" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "physics/body2d/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step }, .has_tests);

    const audio_module = ctx.plugin("ke_audio_module", "src/zig/audio/module", &.{
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-audio-include", b.pathJoin(&.{ src_c, "audio" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-framework-include", b.pathJoin(&.{ src_c, "framework" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "audio/module/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step }, .no_tests);

    const skybox_vs = ctx.shader("skybox", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/skybox/shaders/skybox.slang" }), shaders_out, &.{}, null);
    const skybox_fs = ctx.shader("skybox", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/skybox/shaders/skybox.slang" }), shaders_out, &.{}, null);
    const skybox = ctx.plugin("ke_render_skybox", "src/zig/render/skybox", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-view-include", b.pathJoin(&.{ src_c, "view" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/skybox/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &skybox_vs.step, &skybox_fs.step }, .has_tests);

    const ui_vs = ctx.shader("ui", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/ui/shaders/ui.slang" }), shaders_out, &.{}, null);
    const ui_fs = ctx.shader("ui", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/ui/shaders/ui.slang" }), shaders_out, &.{}, null);
    const ui = ctx.plugin("ke_render_ui", "src/zig/render/ui", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "handle-src", handle_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-text-include", b.pathJoin(&.{ src_c, "text" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/ui/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &ui_vs.step, &ui_fs.step }, .has_tests);

    const shadow_vs = ctx.shader("shadow", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/shadow/shaders/shadow.slang" }), shaders_out, &.{}, null);
    const shadow_fs = ctx.shader("shadow", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/shadow/shaders/shadow.slang" }), shaders_out, &.{}, null);
    const shadow = ctx.plugin("ke_render_shadow", "src/zig/render/shadow", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-view-include", b.pathJoin(&.{ src_c, "view" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/shadow/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &shadow_vs.step, &shadow_fs.step }, .has_tests);

    const cluster_cs = ctx.shader("cluster_cull", "compute", "cs_main", b.pathJoin(&.{ src_zig, "render/cluster/shaders/cluster_cull.slang" }), shaders_out, &.{}, null);
    const cluster = ctx.plugin("ke_render_cluster", "src/zig/render/cluster", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-view-include", b.pathJoin(&.{ src_c, "view" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/cluster/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &cluster_cs.step }, .has_tests);

    const dl_includes = [_][]const u8{ shader_lib_dir, b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders" }) };
    const deferred_lighting_vs = ctx.shader("deferred_lighting", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders/deferred_lighting.slang" }), shaders_out, &dl_includes, null);
    const deferred_lighting_fs = ctx.shader("deferred_lighting", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders/deferred_lighting.slang" }), shaders_out, &dl_includes, null);
    const deferred_lighting = ctx.plugin("ke_render_deferred_lighting", "src/zig/render/deferred_lighting", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-view-include", b.pathJoin(&.{ src_c, "view" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/deferred_lighting/include" })),
        argF(b, "ke-lib-dir", lib_dir),
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
    const gbuffer = ctx.plugin("ke_render_gbuffer", "src/zig/render/gbuffer", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-view-include", b.pathJoin(&.{ src_c, "view" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/gbuffer/include" })),
        argF(b, "ke-lib-dir", lib_dir),
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
    const forward = ctx.plugin("ke_render_forward", "src/zig/render/forward", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-view-include", b.pathJoin(&.{ src_c, "view" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/forward/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step }, .has_tests);
    for (forward_material_shaders) |s| forward.step.dependOn(&s.step);

    const service_gen_dir = b.pathJoin(&.{ ctx.prefix, "gen", "render_service" });
    const magenta_slang = b.pathJoin(&.{ src_zig, "render/service/shaders/magenta.slang" });
    const magenta_vs = ctx.shader("magenta", "vertex", "vs_main", magenta_slang, service_gen_dir, &.{}, null);
    const magenta_fs = ctx.shader("magenta", "fragment", "fs_main", magenta_slang, service_gen_dir, &.{}, null);
    const magenta_vs_wgsl = b.pathJoin(&.{ service_gen_dir, "magenta.vs.wgsl" });
    const magenta_fs_wgsl = b.pathJoin(&.{ service_gen_dir, "magenta.fs.wgsl" });

    const render_service = ctx.plugin("ke_render_service", "src/zig/render/service", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "handle-src", handle_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-framework-include", b.pathJoin(&.{ src_c, "framework" })),
        argF(b, "ke-resource-cache-include", b.pathJoin(&.{ src_c, "resource_cache" })),
        argF(b, "ke-resource-cache-default-include", b.pathJoin(&.{ src_zig, "resource_cache/default/include" })),
        argF(b, "ke-text-include", b.pathJoin(&.{ src_c, "text" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/service/include" })),
        argF(b, "ke-lib-dir", lib_dir),
        argF(b, "magenta-vs-wgsl", magenta_vs_wgsl),
        argF(b, "magenta-fs-wgsl", magenta_fs_wgsl),
    }, &.{
        &common.step,     &resource_cache_default.step,
        &magenta_vs.step, &magenta_fs.step,
    }, .has_tests);

    const render_module = ctx.plugin("ke_render_module", "src/zig/render/module", &.{
        argF(b, "heap-src", heap_src),
        argF(b, "stubs-src", stubs_src),
        argF(b, "ke-math-include", b.pathJoin(&.{ src_c, "math" })),
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-view-include", b.pathJoin(&.{ src_c, "view" })),
        argF(b, "ke-framework-include", b.pathJoin(&.{ src_c, "framework" })),
        argF(b, "ke-text-include", b.pathJoin(&.{ src_c, "text" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-asset-include", b.pathJoin(&.{ src_c, "asset" })),
        argF(b, "ke-service-include", b.pathJoin(&.{ src_zig, "render/service/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/module/include" })),
        argF(b, "ke-view-space-include", b.pathJoin(&.{ src_zig, "view/space/include" })),
        argF(b, "ke-camera-include", b.pathJoin(&.{ src_zig, "render/camera/include" })),
        argF(b, "ke-tonemap-include", b.pathJoin(&.{ src_zig, "render/tonemap/include" })),
        argF(b, "ke-skybox-include", b.pathJoin(&.{ src_zig, "render/skybox/include" })),
        argF(b, "ke-ui-include", b.pathJoin(&.{ src_zig, "render/ui/include" })),
        argF(b, "ke-gbuffer-include", b.pathJoin(&.{ src_zig, "render/gbuffer/include" })),
        argF(b, "ke-shadow-include", b.pathJoin(&.{ src_zig, "render/shadow/include" })),
        argF(b, "ke-cluster-include", b.pathJoin(&.{ src_zig, "render/cluster/include" })),
        argF(b, "ke-deferred-lighting-include", b.pathJoin(&.{ src_zig, "render/deferred_lighting/include" })),
        argF(b, "ke-forward-include", b.pathJoin(&.{ src_zig, "render/forward/include" })),
        argF(b, "ke-lib-dir", lib_dir),
        argF(b, "kerror-src", kerror_src),
    }, &.{
        &common.step,            &render_service.step, &view_space.step,
        &tonemap.step,           &skybox.step,  &ui.step,
        &gbuffer.step,           &shadow.step,  &cluster.step,
        &deferred_lighting.step, &forward.step, &render_camera.step,
    }, .has_tests);

    const all_plugins = [_]*std.Build.Step.Run{
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

    const demo01 = ctx.example("c_demo_01", "examples/c/01_minimal_log", &.{
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "logger" }),
            b.pathJoin(&.{ src_zig, "logger/simple/include" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
        })),
        argF(b, "libs", b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_logger_simple") })),
    }, &.{&logger_simple.step});

    const demo_step = b.step("demo01", "Build examples/c/01_minimal_log");
    demo_step.dependOn(&demo01.step);

    const examples_gen = b.pathJoin(&.{ ctx.prefix, "gen", "examples" });

    {
        var threaded: std.Io.Threaded = .init(b.allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();
        for ([_][]const u8{ "06_triangle", "07_uniform", "08_vertex_buffer", "09_texture", "10_depth" }) |name| {
            std.Io.Dir.cwd().createDirPath(io, b.pathJoin(&.{ examples_gen, name })) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => @panic("failed to create example shader-out-dir"),
            };
        }
    }

    const demo05 = ctx.example("c_demo_05", "examples/c/05_gpu_device", &.{
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        })),
        argF(b, "libs", b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") })),
    }, &.{&gpu_device_webgpu.step});

    const compile_slang_dir = b.pathJoin(&.{ root, "build", "tools", "compile_slang" });
    const compile_slang_dll = b.pathJoin(&.{ compile_slang_dir, "compile_slang.dll" });
    const compile_slang_build = b.addSystemCommand(&.{ "dotnet", "build", b.pathJoin(&.{ root, "scripts/compile_slang.cs" }), "-o", compile_slang_dir, "--nologo", "-v", "q" });
    compile_slang_build.expectExitCode(0);
    compile_slang_build.has_side_effects = true;

    const demo06 = ctx.example("c_demo_06", "examples/c/06_triangle", &.{
        argF(b, "shader-name", "triangle"),
        argF(b, "compile-slang", compile_slang_dll),
        argF(b, "slangc", ctx.slangc_exe),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "06_triangle" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, ctx.slang_step });

    const demo07 = ctx.example("c_demo_07", "examples/c/07_uniform", &.{
        argF(b, "shader-name", "rotate"),
        argF(b, "compile-slang", compile_slang_dll),
        argF(b, "slangc", ctx.slangc_exe),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "07_uniform" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        })),
        "-Dlink-m=true",
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, ctx.slang_step });

    const demo08 = ctx.example("c_demo_08", "examples/c/08_vertex_buffer", &.{
        argF(b, "shader-name", "mesh"),
        argF(b, "compile-slang", compile_slang_dll),
        argF(b, "slangc", ctx.slangc_exe),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "08_vertex_buffer" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, ctx.slang_step });

    const demo09 = ctx.example("c_demo_09", "examples/c/09_texture", &.{
        argF(b, "shader-name", "tex"),
        argF(b, "compile-slang", compile_slang_dll),
        argF(b, "slangc", ctx.slangc_exe),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "09_texture" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, ctx.slang_step });

    const demo10 = ctx.example("c_demo_10", "examples/c/10_depth", &.{
        argF(b, "shader-name", "depth"),
        argF(b, "compile-slang", compile_slang_dll),
        argF(b, "slangc", ctx.slangc_exe),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "10_depth" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "math" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "view" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, ctx.slang_step });

    const demo12 = ctx.example("c_demo_12", "examples/c/12_render_service", &.{
        argF(b, "compile-slang", compile_slang_dll),
        argF(b, "slangc", ctx.slangc_exe),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "12_render_service" })),
        argF(b, "include-dirs", joinPaths(b, &.{
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
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_service") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_module") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, &render_service.step, &render_module.step, &ecs_flecs.step, ctx.slang_step });

    const demo13 = ctx.example("c_demo_13", "examples/c/13_runtime_clear", &.{
        argF(b, "include-dirs", joinPaths(b, &.{
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
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_service") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_module") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
        })),
    }, &.{
        &common.step,    &window_glfw.step,    &gpu_device_webgpu.step, &render_service.step, &render_module.step,
        &ecs_flecs.step, &scheduler_enki.step, &runtime.step,
    });

    const demo14 = ctx.example("c_demo_14", "examples/c/14_forward_mesh", &.{
        argF(b, "include-dirs", joinPaths(b, &.{
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
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_service") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_module") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
        })),
        "-Dlink-m=true",
    }, &.{
        &common.step,    &window_glfw.step,    &gpu_device_webgpu.step, &render_service.step, &render_module.step,
        &ecs_flecs.step, &scheduler_enki.step, &runtime.step,
    });

    const all_examples = [_]*std.Build.Step.Run{
        demo01, demo05, demo06, demo07, demo08, demo09, demo10, demo12, demo13, demo14,
    };
    for ([_]*std.Build.Step.Run{ demo06, demo07, demo08, demo09, demo10, demo12 }) |e| e.step.dependOn(&compile_slang_build.step);
    for (all_examples) |e| b.getInstallStep().dependOn(&e.step);
}

const Tests = enum { has_tests, no_tests };

const Ctx = struct {
    b: *std.Build,
    root: []const u8,
    zig_exe: []const u8,
    prefix: []const u8,
    /// Every sub-invocation is told to cache here, so one build tree holds one
    /// cache instead of one per plugin directory.
    cache_dir: []const u8,
    release_flag: []const u8,
    vcpkg_step: *std.Build.Step,
    target_arg: []const u8,
    slangc_exe: []const u8,
    slang_step: *std.Build.Step,
    plugins_step: *std.Build.Step,
    test_step: *std.Build.Step,
    exe_suffix: []const u8,
    run_under_wine: bool,
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
    fn plugin(ctx: *Ctx, name: []const u8, dir: []const u8, extra_args: []const []const u8, deps: []const *std.Build.Step, tests: Tests) *std.Build.Step.Run {
        const b = ctx.b;
        const cwd = b.pathJoin(&.{ b.build_root.path.?, dir });
        const child_cache = b.pathJoin(&.{ ctx.cache_dir, "plugins", name });
        const run = b.addSystemCommand(&.{ ctx.zig_exe, "build", "--prefix", ctx.prefix, "--cache-dir", child_cache });
        run.addArgs(extra_args);
        run.addArg(ctx.release_flag);
        if (ctx.target_arg.len != 0) run.addArg(ctx.target_arg);
        run.setCwd(.{ .cwd_relative = cwd });
        run.step.dependOn(ctx.vcpkg_step);
        for (deps) |d| run.step.dependOn(d);
        run.expectExitCode(0);
        run.has_side_effects = true;
        run.setName(b.fmt("build {s} (Zig)", .{name}));
        ctx.plugins_step.dependOn(&run.step);

        switch (tests) {
            .no_tests => {},
            .has_tests => {
                const t = b.addSystemCommand(&.{ ctx.zig_exe, "build", "test", "--summary", "new", "--prefix", ctx.prefix, "--cache-dir", child_cache });
                t.addArgs(extra_args);
                t.addArg(ctx.release_flag);
                if (ctx.target_arg.len != 0) t.addArg(ctx.target_arg);
                if (ctx.run_under_wine) t.addArg("-fwine");
                t.setCwd(.{ .cwd_relative = cwd });
                t.expectExitCode(0);
                t.has_side_effects = true;
                t.step.dependOn(ctx.plugins_step);
                t.setName(b.fmt("test {s} (Zig)", .{name}));
                ctx.test_step.dependOn(&t.step);
            },
        }
        return run;
    }

    /// Like `plugin`, but for a C example: every example's own build.zig
    /// hardcodes its exe name to "demo" and installs to "bin" under whatever
    /// --prefix it is given, so pointing several examples at the shared engine
    /// prefix would make each one overwrite the last one's binary. Each example
    /// gets its own private sub-prefix instead, and the resulting "demo" binary
    /// is copied into the shared prefix's bin/ under its own name.
    fn example(ctx: *Ctx, demo_name: []const u8, dir: []const u8, extra_args: []const []const u8, deps: []const *std.Build.Step) *std.Build.Step.Run {
        const b = ctx.b;
        const own_prefix = b.pathJoin(&.{ ctx.prefix, "examples-out", demo_name });
        const run = b.addSystemCommand(&.{ ctx.zig_exe, "build", "--prefix", own_prefix, "--cache-dir", b.pathJoin(&.{ ctx.cache_dir, "plugins", demo_name }) });
        run.addArgs(extra_args);
        run.addArg(ctx.release_flag);
        if (ctx.target_arg.len != 0) run.addArg(ctx.target_arg);
        run.setCwd(.{ .cwd_relative = b.pathJoin(&.{ b.build_root.path.?, dir }) });
        run.step.dependOn(ctx.vcpkg_step);
        for (deps) |d| run.step.dependOn(d);
        run.expectExitCode(0);
        run.has_side_effects = true;
        run.setName(b.fmt("build {s} (Zig)", .{demo_name}));

        const copy = b.addSystemCommand(&.{
            "install", "-Dm755",
            b.pathJoin(&.{ own_prefix, "bin", b.fmt("demo{s}", .{ctx.exe_suffix}) }),
            b.pathJoin(&.{ ctx.prefix, "bin", b.fmt("{s}{s}", .{ demo_name, ctx.exe_suffix }) }),
        });
        copy.step.dependOn(&run.step);
        copy.setName(b.fmt("install {s}", .{demo_name}));
        return copy;
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

fn argF(b: *std.Build, comptime name: []const u8, value: []const u8) []const u8 {
    return b.fmt("-D" ++ name ++ "={s}", .{value});
}
