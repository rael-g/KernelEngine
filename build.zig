const std = @import("std");

// The engine's build orchestrator, replacing CMake. vcpkg (manifest mode,
// vcpkg.json + vcpkg-configuration.json at repo root) is invoked directly —
// no CMake toolchain file involved, confirmed to work standalone. Every
// engine plugin already builds itself via its own build.zig (a leftover of
// the CMake-driven "zig build" custom commands); this file's job is purely
// to invoke each one, in dependency order, with a shared --prefix so every
// .so converges into one output/lib directory and every consumer needs only
// one rpath entry to find them all.
//
// Scope note: this currently wires the non-render plugin chain (everything
// through ke_framework/ke_window_glfw/asset+audio+text backends/box2d) plus
// one example end to end. The render pipeline (ke_gpu_device_webgpu + the 11
// render/* modules, which also drive Slang/GLSL shader generation) and the
// remaining examples/tests are follow-up work — see docs/RuntimeArchitectureV2.md
// for what's tracked.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const debug = optimize == .Debug;

    const root = b.build_root.path orelse @panic("build.zig must run from the repo root");
    // Forwarded only to the two GTest suites (system clang++-built): they're
    // the only native binaries whose linker (system, not Zig's own) can
    // handle Clang's profiling-runtime relocations. See tests/c/kernel/build.zig.
    const coverage = b.option(bool, "coverage", "instrument the GTest suites for Clang source-based coverage") orelse false;

    // vcpkg dependencies build with `zig cc`/`zig c++`
    // (vcpkg-triplets/x64-{windows,linux}-zig.cmake) instead of the system
    // toolchain — no Visual Studio/SDK or system C/C++ toolchain required.
    const triplet = switch (target.result.os.tag) {
        .windows => "x64-windows-zig",
        else => "x64-linux-zig",
    };

    // ── vcpkg (fetched, not a system dependency) ─────────────────────────────
    // vcpkg itself is a small orchestrator binary (microsoft/vcpkg-tool) plus
    // the scripts/triplets it needs to run standalone (the "standalone
    // bundle" release asset) — fetched the same way wgpu-native/Slang are.
    // Port recipes and the C/C++ library sources they build are resolved by
    // vcpkg itself at install time via its git registry (vcpkg-configuration.json),
    // same as any vcpkg install; that isn't something a build-time fetch can
    // shortcut. `-Dvcpkg-root=`/`$VCPKG_ROOT` still override this for anyone
    // who already has vcpkg installed.
    const vcpkg_tool_version = "2026-07-13";
    const vcpkg_dir_default = b.pathJoin(&.{ root, ".cache", b.fmt("vcpkg-{s}", .{vcpkg_tool_version}) });
    const vcpkg_root = b.option([]const u8, "vcpkg-root", "path to the vcpkg checkout") orelse
        b.graph.environ_map.get("VCPKG_ROOT") orelse
        vcpkg_dir_default;
    const vcpkg_exe = b.pathJoin(&.{ vcpkg_root, if (target.result.os.tag == .windows) "vcpkg.exe" else "vcpkg" });
    const vcpkg_bundle_url = b.fmt("https://github.com/microsoft/vcpkg-tool/releases/download/{s}/vcpkg-standalone-bundle.tar.gz", .{vcpkg_tool_version});
    const vcpkg_bin_asset = if (target.result.os.tag == .windows) "vcpkg.exe" else "vcpkg-glibc";
    const vcpkg_bin_url = b.fmt("https://github.com/microsoft/vcpkg-tool/releases/download/{s}/{s}", .{ vcpkg_tool_version, vcpkg_bin_asset });
    const vcpkg_bundle_tar = b.pathJoin(&.{ vcpkg_root, "bundle.tar.gz" });
    const vcpkg_fetch = b.addSystemCommand(&.{
        "sh", "-c",
        b.fmt(
            "mkdir -p '{s}' && ([ -f '{s}' ] || (curl -fsSL -o '{s}' '{s}' && tar -xzf '{s}' -C '{s}' && curl -fsSL -o '{s}' '{s}' && chmod +x '{s}'))",
            .{ vcpkg_root, vcpkg_exe, vcpkg_bundle_tar, vcpkg_bundle_url, vcpkg_bundle_tar, vcpkg_root, vcpkg_exe, vcpkg_bin_url, vcpkg_exe },
        ),
    });

    // ── vcpkg (manifest mode) ────────────────────────────────────────────────
    const vcpkg_installed = b.pathJoin(&.{ root, "vcpkg_installed_zig" });
    const vcpkg_overlay_triplets = b.pathJoin(&.{ root, "vcpkg-triplets" });
    var vcpkg_install_args: std.ArrayList([]const u8) = .empty;
    vcpkg_install_args.appendSlice(b.allocator, &.{
        vcpkg_exe,
        "install",
        b.fmt("--triplet={s}", .{triplet}),
        b.fmt("--x-manifest-root={s}", .{root}),
        b.fmt("--x-install-root={s}", .{vcpkg_installed}),
        b.fmt("--overlay-triplets={s}", .{vcpkg_overlay_triplets}),
        b.fmt("--host-triplet={s}", .{triplet}),
    }) catch @panic("OOM");
    const vcpkg_install = b.addSystemCommand(vcpkg_install_args.items);
    vcpkg_install.step.dependOn(&vcpkg_fetch.step);

    const vcpkg_include = b.pathJoin(&.{ vcpkg_installed, triplet, "include" });
    const vcpkg_lib_release = b.pathJoin(&.{ vcpkg_installed, triplet, "lib" });
    const vcpkg_lib = if (debug) b.pathJoin(&.{ vcpkg_installed, triplet, "debug", "lib" }) else vcpkg_lib_release;
    // gtest/gmock's *_main archives live one level down, under manual-link —
    // needed once tests join this build.
    // const vcpkg_manual_link = b.pathJoin(&.{ vcpkg_lib, "manual-link" });

    // ── shared paths ─────────────────────────────────────────────────────────
    const src_c = b.pathJoin(&.{ root, "src/c" });
    const src_zig = b.pathJoin(&.{ root, "src/zig" });
    const kerror_src = b.pathJoin(&.{ src_zig, "common/kerror.zig" });
    // Single shared tomlc99 copy, consumed by every plugin that parses TOML
    // (ke_framework, ke_configuration_toml).
    const tomlc99_dir = b.pathJoin(&.{ src_zig, "common/third_party/tomlc99" });
    // Absolute, always: each plugin's `zig build` runs with its OWN directory
    // as cwd, so a relative --prefix here would resolve against the wrong
    // place there.
    const absolute_prefix = if (std.fs.path.isAbsolute(b.install_prefix))
        b.install_prefix
    else
        b.pathJoin(&.{ root, b.install_prefix });

    // ── Slang toolchain (fetched, not a system dependency) ──────────────────
    // slangc is a standalone shader-slang/slang release — no Vulkan SDK
    // linkage — fetched the same way wgpu-native is: a direct release archive
    // download, cached under .cache/, no system package or PATH entry needed.
    const slang_version = "2025.17.2";
    const slang_url_name = switch (target.result.os.tag) {
        .windows => b.fmt("slang-{s}-windows-x86_64", .{slang_version}),
        else => b.fmt("slang-{s}-linux-x86_64", .{slang_version}),
    };
    const slang_dir = b.pathJoin(&.{ root, ".cache", slang_url_name });
    const slang_zip = b.pathJoin(&.{ slang_dir, "slang.zip" });
    const slang_url = b.fmt("https://github.com/shader-slang/slang/releases/download/v{s}/{s}.zip", .{ slang_version, slang_url_name });
    const slangc_exe = b.pathJoin(&.{ slang_dir, "bin", if (target.result.os.tag == .windows) "slangc.exe" else "slangc" });
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
        .release_flag = if (debug) "--release=off" else "--release=fast",
        .vcpkg_step = &vcpkg_install.step,
        .target_arg = if (target.result.os.tag == .windows) "-Dtarget=x86_64-windows-gnu" else "",
        .slangc_exe = slangc_exe,
        .slang_step = &slang_fetch.step,
    };

    // ── kernel built-ins ─────────────────────────────────────────────────────
    const common = ctx.plugin("ke_common", "src/zig/common", &.{}, &.{});

    const logger_simple = ctx.plugin("ke_logger_simple", "src/zig/logger/simple", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const ecs_flecs = ctx.plugin("ke_ecs_flecs", "src/zig/ecs/flecs", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "flecs-include", vcpkg_include),
        argF(b, "flecs-lib", b.pathJoin(&.{ vcpkg_lib, "libflecs_static.a" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const input_default = ctx.plugin("ke_input_default", "src/zig/input/default", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-input-include", b.pathJoin(&.{ src_c, "input" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const resource_cache_default = ctx.plugin("ke_resource_cache_default", "src/zig/resource_cache/default", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-resource-cache-include", b.pathJoin(&.{ src_c, "resource_cache" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const scheduler_enki = ctx.plugin("ke_scheduler_enki", "src/zig/scheduler/enki", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
        argF(b, "enki-include", b.pathJoin(&.{ vcpkg_include, "enkiTS" })),
        argF(b, "enki-lib", vcpkg_lib),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const runtime = ctx.plugin("ke_runtime", "src/zig/runtime", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const framework = ctx.plugin("ke_framework", "src/zig/framework", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-input-include", b.pathJoin(&.{ src_c, "input" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-asset-include", b.pathJoin(&.{ src_c, "asset" })),
        argF(b, "ke-text-include", b.pathJoin(&.{ src_c, "text" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
        argF(b, "kerror-src", kerror_src),
        argF(b, "tomlc99-dir", tomlc99_dir),
    }, &.{});

    const window_glfw = ctx.plugin("ke_window_glfw", "src/zig/window/glfw", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-window-include", b.pathJoin(&.{ src_c, "window" })),
        argF(b, "ke-input-include", b.pathJoin(&.{ src_c, "input" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "glfw-include", vcpkg_include),
        argF(b, "glfw-lib", vcpkg_lib),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const asset_stb_image = ctx.plugin("ke_asset_stb_image", "src/zig/asset/stb_image", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-asset-include", b.pathJoin(&.{ src_c, "asset" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "asset/stb_image/include" })),
        argF(b, "stb-include", vcpkg_include),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const audio_miniaudio = ctx.plugin("ke_audio_miniaudio", "src/zig/audio/miniaudio", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-audio-include", b.pathJoin(&.{ src_c, "audio" })),
        argF(b, "ke-resource-cache-include", b.pathJoin(&.{ src_c, "resource_cache" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "audio/miniaudio/include" })),
        argF(b, "miniaudio-include", vcpkg_include),
        argF(b, "ke-resource-cache-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{&resource_cache_default.step});

    const text_stb_truetype = ctx.plugin("ke_text_stb_truetype", "src/zig/text/stb_truetype", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-text-include", b.pathJoin(&.{ src_c, "text" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "text/stb_truetype/include" })),
        argF(b, "stb-include", vcpkg_include),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const physics_box2d = ctx.plugin("ke_physics_2d_box2d", "src/zig/physics/box2d", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-physics-include", b.pathJoin(&.{ src_c, "physics" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "box2d-include", vcpkg_include),
        argF(b, "box2d-lib", b.pathJoin(&.{ vcpkg_lib, if (debug) "libbox2dd.a" else "libbox2d.a" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    // vcpkg's zlib/minizip ports name their static archives "z"/"minizip" on
    // x64-linux but "zs"/"minizips" under our x64-windows-zig triplet (port
    // CMakeLists quirk, not something this build controls).
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
    }, &.{});

    const configuration = ctx.plugin("ke_configuration", "src/zig/configuration", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-config-include", b.pathJoin(&.{ src_c, "configuration" })),
        argF(b, "ke-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
    }, &.{&common.step});

    const configuration_toml = ctx.plugin("ke_configuration_toml", "src/zig/configuration/toml", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-config-include", b.pathJoin(&.{ src_c, "configuration" })),
        argF(b, "ke-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
        argF(b, "tomlc99-dir", tomlc99_dir),
    }, &.{&common.step});

    // ── WebGPU backend ───────────────────────────────────────────────────────
    // CMake fetched this through eliemichel/WebGPU-distribution, a wrapper
    // repo whose only job (for our config) is to download the same prebuilt
    // wgpu-native release archive this fetches directly — cutting out a git
    // clone of a whole wrapper project to reach one URL its own CMake was
    // going to build anyway.
    const wgpu_version = "v24.0.3.1";
    const wgpu_url_name = switch (target.result.os.tag) {
        .windows => "wgpu-windows-x86_64-msvc-release",
        else => "wgpu-linux-x86_64-release",
    };
    const wgpu_dir = b.pathJoin(&.{ root, ".cache", wgpu_url_name });
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
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-window-include", b.pathJoin(&.{ src_c, "window" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
        argF(b, "wgpu-include", wgpu_include),
        argF(b, "wgpu-lib", wgpu_lib_dir),
    }, &.{ &common.step, &wgpu_fetch.step });

    // wgpu-native is linked dynamically: every consumer needs its .so beside
    // them at runtime. Copied into the shared lib dir once, here, rather than
    // every consumer computing its own rpath into the .cache tree.
    const wgpu_copy = b.addSystemCommand(&.{
        "cp", "-f",
        b.pathJoin(&.{ wgpu_lib_dir, wgpu_native_filename }),
        b.pathJoin(&.{ ctx.prefix, "lib", wgpu_native_filename }),
    });
    wgpu_copy.step.dependOn(&gpu_device_webgpu.step);

    // ── render pipeline: 6 standalone passes (plain slang, no material system) ─
    const lib_dir = b.pathJoin(&.{ ctx.prefix, "lib" });
    const shaders_out = b.pathJoin(&.{ ctx.prefix, "bin", "shaders" });
    const shader_lib_dir = b.pathJoin(&.{ root, "src/shaders" });

    const tonemap_vs = ctx.shader("tonemap", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/tonemap/shaders/tonemap.slang" }), shaders_out, &.{});
    const tonemap_fs = ctx.shader("tonemap", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/tonemap/shaders/tonemap.slang" }), shaders_out, &.{});
    const tonemap = ctx.plugin("ke_render_tonemap", "src/zig/render/tonemap", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/tonemap/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &tonemap_vs.step, &tonemap_fs.step });

    const skybox_vs = ctx.shader("skybox", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/skybox/shaders/skybox.slang" }), shaders_out, &.{});
    const skybox_fs = ctx.shader("skybox", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/skybox/shaders/skybox.slang" }), shaders_out, &.{});
    const skybox = ctx.plugin("ke_render_skybox", "src/zig/render/skybox", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/skybox/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step, &skybox_vs.step, &skybox_fs.step });

    const ui_vs = ctx.shader("ui", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/ui/shaders/ui.slang" }), shaders_out, &.{});
    const ui_fs = ctx.shader("ui", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/ui/shaders/ui.slang" }), shaders_out, &.{});
    const ui = ctx.plugin("ke_render_ui", "src/zig/render/ui", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/ui/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step, &ui_vs.step, &ui_fs.step });

    const shadow_vs = ctx.shader("shadow", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/shadow/shaders/shadow.slang" }), shaders_out, &.{});
    const shadow_fs = ctx.shader("shadow", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/shadow/shaders/shadow.slang" }), shaders_out, &.{});
    const shadow = ctx.plugin("ke_render_shadow", "src/zig/render/shadow", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/shadow/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step, &shadow_vs.step, &shadow_fs.step });

    const cluster_cs = ctx.shader("cluster_cull", "compute", "cs_main", b.pathJoin(&.{ src_zig, "render/cluster/shaders/cluster_cull.slang" }), shaders_out, &.{});
    const cluster = ctx.plugin("ke_render_cluster", "src/zig/render/cluster", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/cluster/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step, &cluster_cs.step });

    const dl_includes = [_][]const u8{ shader_lib_dir, b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders" }) };
    const deferred_lighting_vs = ctx.shader("deferred_lighting", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders/deferred_lighting.slang" }), shaders_out, &dl_includes);
    const deferred_lighting_fs = ctx.shader("deferred_lighting", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders/deferred_lighting.slang" }), shaders_out, &dl_includes);
    const deferred_lighting = ctx.plugin("ke_render_deferred_lighting", "src/zig/render/deferred_lighting", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/deferred_lighting/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step, &deferred_lighting_vs.step, &deferred_lighting_fs.step });

    // ── render pipeline: material-system passes (gbuffer, forward) ──────────
    // Every authored material × this pass, the cartesian product each pass
    // would otherwise have to hardcode. Mirrors cmake/CompileMaterialShaders.cmake's
    // ke_compile_material_shaders: glob every KE_MATERIALS_DIRS directory
    // (engine defaults + a downstream example's own materials tree, proving a
    // game can author materials without touching engine source), generate a
    // per-(material,pass) wrapper via generate_material_wrapper.cs, then
    // compile it the same way any other pass shader compiles.
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
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/gbuffer/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step });
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
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/forward/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step });
    for (forward_material_shaders) |s| forward.step.dependOn(&s.step);

    // ke_render_service: the forward-renderer aggregator. Its @embedFile of the
    // magenta fallback shader means those two WGSL files must exist on disk
    // BEFORE core's own `zig build` starts — a harder ordering constraint than
    // a normal link dependency, so the compile steps are threaded into core's
    // deps explicitly rather than relying on the shared shaders_out directory
    // existing by coincidence.
    const service_gen_dir = b.pathJoin(&.{ ctx.prefix, "gen", "render_service" });
    const magenta_slang = b.pathJoin(&.{ src_zig, "render/service/shaders/magenta.slang" });
    const magenta_vs = ctx.shader("magenta", "vertex", "vs_main", magenta_slang, service_gen_dir, &.{});
    const magenta_fs = ctx.shader("magenta", "fragment", "fs_main", magenta_slang, service_gen_dir, &.{});
    const magenta_vs_wgsl = b.pathJoin(&.{ service_gen_dir, "magenta.vs.wgsl" });
    const magenta_fs_wgsl = b.pathJoin(&.{ service_gen_dir, "magenta.fs.wgsl" });

    const render_service = ctx.plugin("ke_render_service", "src/zig/render/service", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-resource-cache-include", b.pathJoin(&.{ src_c, "resource_cache" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/service/include" })),
        argF(b, "ke-tonemap-include", b.pathJoin(&.{ src_zig, "render/tonemap/include" })),
        argF(b, "ke-skybox-include", b.pathJoin(&.{ src_zig, "render/skybox/include" })),
        argF(b, "ke-ui-include", b.pathJoin(&.{ src_zig, "render/ui/include" })),
        argF(b, "ke-gbuffer-include", b.pathJoin(&.{ src_zig, "render/gbuffer/include" })),
        argF(b, "ke-shadow-include", b.pathJoin(&.{ src_zig, "render/shadow/include" })),
        argF(b, "ke-cluster-include", b.pathJoin(&.{ src_zig, "render/cluster/include" })),
        argF(b, "ke-deferred-lighting-include", b.pathJoin(&.{ src_zig, "render/deferred_lighting/include" })),
        argF(b, "ke-forward-include", b.pathJoin(&.{ src_zig, "render/forward/include" })),
        argF(b, "ke-lib-dir", lib_dir),
        argF(b, "magenta-vs-wgsl", magenta_vs_wgsl),
        argF(b, "magenta-fs-wgsl", magenta_fs_wgsl),
    }, &.{
        &common.step,           &resource_cache_default.step, &runtime.step,
        &tonemap.step,          &skybox.step,                 &ui.step,
        &gbuffer.step,          &shadow.step,                 &cluster.step,
        &deferred_lighting.step, &forward.step,
        &magenta_vs.step,       &magenta_fs.step,
    });

    // Every plugin is an independent `zig build` process invocation, not a
    // real Zig module dependency — nothing here transitively pulls the others
    // in, so the default install step must list every one explicitly (unlike
    // a normal Zig dependency graph, where depending on the leaf would do it).
    const all_plugins = [_]*std.Build.Step.Run{
        common,          logger_simple,     ecs_flecs,           input_default,
        resource_cache_default, scheduler_enki, runtime,         framework,
        window_glfw,     asset_stb_image,   audio_miniaudio,     text_stb_truetype,
        physics_box2d,   asset_assimp,      configuration,       configuration_toml,
        tonemap,         skybox,            ui,                  shadow,
        cluster,         deferred_lighting, gpu_device_webgpu,   gbuffer,
        forward,         render_service,
    };
    for (all_plugins) |p| b.getInstallStep().dependOn(&p.step);
    b.getInstallStep().dependOn(&wgpu_copy.step);

    // Windows has no rpath equivalent: a consumer .exe in bin/ won't find its
    // dependency .dlls sitting in a sibling lib/ the way a Linux binary finds
    // its .so via -rpath. Every plugin still installs to lib/ (matching Linux,
    // and matching where the .lib import libraries the link step needs live),
    // so the fix is a straight copy of the built .dlls into bin/ once, here —
    // matching the "C# expects native libraries at build/native/bin/" contract
    // CLAUDE.md already documents for the managed side.
    if (target.result.os.tag == .windows) {
        const copy_dlls_to_bin = b.addSystemCommand(&.{
            "sh", "-c",
            b.fmt("cp -f '{s}'/*.dll '{s}'/", .{ lib_dir, b.pathJoin(&.{ ctx.prefix, "bin" }) }),
        });
        for (all_plugins) |p| copy_dlls_to_bin.step.dependOn(&p.step);
        copy_dlls_to_bin.step.dependOn(&wgpu_copy.step);
        copy_dlls_to_bin.setName("copy plugin DLLs into bin/");
        b.getInstallStep().dependOn(&copy_dlls_to_bin.step);
    }

    // ── GTest suites (system C++ compiler — Zig's own libc++ is ABI-incompatible
    // with vcpkg's libstdc++-built GTest archives) ──────────────────────────────
    const gtest_include = vcpkg_include;
    const gtest_a = b.pathJoin(&.{ vcpkg_lib, "libgtest.a" });
    const gtest_main_a = b.pathJoin(&.{ vcpkg_lib, "manual-link", "libgtest_main.a" });
    const gmock_a = b.pathJoin(&.{ vcpkg_lib, "libgmock.a" });
    const tests_c_kernel = b.pathJoin(&.{ root, "tests/c/kernel" });
    const tests_integration_cpp = b.pathJoin(&.{ root, "tests/integration/cpp" });

    const kernel_test_sources = [_][]const u8{
        "test_input.cpp",         "test_logger.cpp",       "test_asset_resolver.cpp",
        "test_resource_cache.cpp", "test_scene_tree.cpp",  "test_input_actions.cpp",
        "test_scene_loader.cpp",
    };
    var kernel_test_sources_abs: [kernel_test_sources.len][]const u8 = undefined;
    for (kernel_test_sources, 0..) |s, i| kernel_test_sources_abs[i] = b.pathJoin(&.{ tests_c_kernel, s });

    const test_ke_kernel = ctx.testBinary("test_ke_kernel", "tests/c/kernel", std.mem.concat(b.allocator, []const u8, &.{
        &.{
        b.fmt("-Dcoverage={}", .{coverage}),
        argF(b, "sources", joinPaths(b, &kernel_test_sources_abs)),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "logger" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_c, "spatial" }),
            b.pathJoin(&.{ src_c, "scheduler" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "input" }),
            b.pathJoin(&.{ src_c, "asset" }),
            b.pathJoin(&.{ src_c, "resource_cache" }),
            b.pathJoin(&.{ src_c, "text" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_c, "runtime" }),
            b.pathJoin(&.{ src_zig, "framework/include" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
            b.pathJoin(&.{ src_zig, "scheduler/enki/include" }),
            gtest_include,
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_logger_simple") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_input_default") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_resource_cache_default") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_framework") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            gtest_main_a,
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            gtest_a,
        })),
        argF(b, "rpaths", lib_dir),
        argF(b, "output", b.pathJoin(&.{ ctx.prefix, "bin", exeFileName(b, target, "test_ke_kernel") })),
        },
        testCxxArgs(b, target, root),
    }) catch @panic("OOM"), &.{
        &logger_simple.step, &input_default.step, &resource_cache_default.step, &framework.step,
        &runtime.step,       &ecs_flecs.step,      &scheduler_enki.step,        &common.step,
    });

    const integration_test_sources = [_][]const u8{
        "test_world.cpp",           "test_factories.cpp",        "test_window_glfw.cpp",
        "test_asset_loader.cpp",    "test_stb_image_loader.cpp", "test_enki_scheduler.cpp",
        "test_miniaudio_audio.cpp", "test_box2d_physics.cpp",    "test_stb_font.cpp",
        "test_runtime.cpp",         "test_ecs_parallel_reads.cpp",
    };
    var integration_test_sources_abs: [integration_test_sources.len][]const u8 = undefined;
    for (integration_test_sources, 0..) |s, i| integration_test_sources_abs[i] = b.pathJoin(&.{ tests_integration_cpp, s });

    const test_integration_cpp = ctx.testBinary("test_integration_cpp", "tests/integration/cpp", std.mem.concat(b.allocator, []const u8, &.{
        &.{
        b.fmt("-Dcoverage={}", .{coverage}),
        argF(b, "sources", joinPaths(b, &integration_test_sources_abs)),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_c, "spatial" }),
            b.pathJoin(&.{ src_c, "scheduler" }),
            b.pathJoin(&.{ src_c, "physics" }),
            b.pathJoin(&.{ src_c, "logger" }),
            b.pathJoin(&.{ src_c, "input" }),
            b.pathJoin(&.{ src_c, "resource_cache" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_zig, "scheduler/enki/include" }),
            b.pathJoin(&.{ src_zig, "audio/miniaudio/include" }),
            b.pathJoin(&.{ src_zig, "physics/box2d/include" }),
            b.pathJoin(&.{ src_zig, "text/stb_truetype/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "asset/assimp/include" }),
            b.pathJoin(&.{ src_c, "asset" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_c, "text" }),
            b.pathJoin(&.{ src_zig, "asset/stb_image/include" }),
            b.pathJoin(&.{ src_c, "audio" }),
            b.pathJoin(&.{ src_c, "runtime" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
            b.pathJoin(&.{ src_zig, "framework/include" }),
            gtest_include,
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_asset_assimp") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_asset_stb_image") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_audio_miniaudio") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_physics_2d_box2d") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_text_stb_truetype") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_logger_simple") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_input_default") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_resource_cache_default") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_framework") }),
            gtest_main_a,
            gmock_a,
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            gtest_a,
        })),
        argF(b, "rpaths", lib_dir),
        argF(b, "output", b.pathJoin(&.{ ctx.prefix, "bin", exeFileName(b, target, "test_integration_cpp") })),
        },
        testCxxArgs(b, target, root),
    }) catch @panic("OOM"), &.{
        &window_glfw.step,       &asset_assimp.step,          &asset_stb_image.step,
        &scheduler_enki.step,    &audio_miniaudio.step,       &physics_box2d.step,
        &text_stb_truetype.step, &logger_simple.step,         &input_default.step,
        &resource_cache_default.step, &runtime.step,          &ecs_flecs.step,
        &framework.step,         &common.step,
    });

    const test_step = b.step("test", "Build the two GTest suites (system C++ compiler)");
    test_step.dependOn(&test_ke_kernel.step);
    test_step.dependOn(&test_integration_cpp.step);
    b.getInstallStep().dependOn(&test_ke_kernel.step);
    b.getInstallStep().dependOn(&test_integration_cpp.step);

    // ── C examples ───────────────────────────────────────────────────────────
    // Every example's own build.zig hardcodes exe name "demo" installed to its
    // own prefix's bin/ — fine in isolation, but a shared --prefix across all
    // of them would make every later example overwrite the previous one's
    // binary. Each example instead builds into its own private sub-prefix,
    // then gets copied into the shared bin/ under its own c_demo_NN name —
    // the same two-path pattern CMake used to dodge the IMPORTED_LOCATION
    // collision bug, applied here to dodge an install-path collision instead.
    const demo01 = ctx.example("c_demo_01", "examples/c/01_minimal_log", &.{
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "logger" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
        })),
        argF(b, "libs", b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_logger_simple") })),
    }, &.{&logger_simple.step});

    const demo_step = b.step("demo01", "Build examples/c/01_minimal_log with zero CMake involved");
    demo_step.dependOn(&demo01.step);

    // ── remaining C examples ────────────────────────────────────────────────
    const examples_gen = b.pathJoin(&.{ ctx.prefix, "gen", "examples" });

    // glslangValidator (unlike compile_slang.cs) never creates its own output
    // directory — it just fails with "Failed to open file" the first time
    // zig-out doesn't exist yet, so every glslang-driven example's shader dir
    // is created up front, mirroring CMake's file(MAKE_DIRECTORY ...) calls.
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
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
        })),
        argF(b, "libs", b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") })),
    }, &.{&gpu_device_webgpu.step});

    const demo06 = ctx.example("c_demo_06", "examples/c/06_triangle", &.{
        argF(b, "shader-name", "triangle"),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "06_triangle" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step });

    const demo07 = ctx.example("c_demo_07", "examples/c/07_uniform", &.{
        argF(b, "shader-name", "rotate"),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "07_uniform" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        })),
        "-Dlink-m=true",
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step });

    const demo08 = ctx.example("c_demo_08", "examples/c/08_vertex_buffer", &.{
        argF(b, "shader-name", "mesh"),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "08_vertex_buffer" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step });

    const demo09 = ctx.example("c_demo_09", "examples/c/09_texture", &.{
        argF(b, "shader-name", "tex"),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "09_texture" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step });

    const demo10 = ctx.example("c_demo_10", "examples/c/10_depth", &.{
        argF(b, "shader-name", "depth"),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "10_depth" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step });

    const demo12 = ctx.example("c_demo_12", "examples/c/12_render_service", &.{
        argF(b, "compile-slang", b.pathJoin(&.{ root, "scripts/compile_slang.cs" })),
        argF(b, "slangc", ctx.slangc_exe),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "12_render_service" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_zig, "render/service/include" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_service") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, &render_service.step, &ecs_flecs.step, ctx.slang_step });

    const demo13 = ctx.example("c_demo_13", "examples/c/13_runtime_clear", &.{
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_c, "scheduler" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_zig, "render/service/include" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
            b.pathJoin(&.{ src_zig, "scheduler/enki/include" }),
            b.pathJoin(&.{ src_c, "runtime" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_service") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
        })),
    }, &.{
        &common.step,     &window_glfw.step, &gpu_device_webgpu.step, &render_service.step,
        &ecs_flecs.step,  &scheduler_enki.step, &runtime.step,
    });

    const demo14 = ctx.example("c_demo_14", "examples/c/14_forward_mesh", &.{
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "spatial" }),
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_c, "scheduler" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_zig, "render/service/include" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
            b.pathJoin(&.{ src_zig, "scheduler/enki/include" }),
            b.pathJoin(&.{ src_c, "runtime" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_service") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
        })),
        "-Dlink-m=true",
    }, &.{
        &common.step,     &window_glfw.step, &gpu_device_webgpu.step, &render_service.step,
        &ecs_flecs.step,  &scheduler_enki.step, &runtime.step,
    });

    const all_examples = [_]*std.Build.Step.Run{
        demo01, demo05, demo06, demo07, demo08, demo09, demo10, demo12, demo13, demo14,
    };
    for (all_examples) |e| b.getInstallStep().dependOn(&e.step);
}

const Ctx = struct {
    b: *std.Build,
    root: []const u8,
    zig_exe: []const u8,
    prefix: []const u8,
    release_flag: []const u8,
    vcpkg_step: *std.Build.Step,
    // Forwarded to every sub-`zig build` invocation. Some plugins pin
    // `.default_target = .{ .abi = .gnu }` themselves (ke_common and other
    // "pure-logic" built-ins); most don't, including every example and test
    // binary. Left unset, Zig's native-target resolution picks the msvc ABI
    // on Windows even with no MSVC installed — a mix of gnu-ABI plugin DLLs
    // and an msvc-ABI host .exe fails to load at runtime (STATUS_DLL_NOT_FOUND
    // on a UCRT forwarder). Forcing the same target everywhere, from the one
    // place that already knows the triplet story, is simpler than auditing
    // every sub-build.zig for a consistent default.
    target_arg: []const u8,
    slangc_exe: []const u8,
    slang_step: *std.Build.Step,

    /// Compiles one Slang entry point to WGSL via scripts/compile_slang.cs,
    /// mirroring cmake/CompileSlangShader.cmake's ke_compile_slang_shader.
    /// Every render pass loads its shaders at runtime by logical name via
    /// ke_render_service::load_shader, so the output always lands in the one
    /// shared runtime shaders directory, never embedded in a plugin's own .so
    /// (render/service's own embedded fallback shader is the one exception —
    /// handled separately, since @embedFile needs the file before that
    /// module's own `zig build` even starts).
    fn shader(ctx: *Ctx, name: []const u8, stage: []const u8, entry: []const u8, input: []const u8, out_dir: []const u8, includes: []const []const u8) *std.Build.Step.Run {
        const b = ctx.b;
        const suffix = if (std.mem.eql(u8, stage, "vertex"))
            "vs"
        else if (std.mem.eql(u8, stage, "fragment"))
            "fs"
        else
            "cs";
        const out_file = b.pathJoin(&.{ out_dir, b.fmt("{s}.{s}.wgsl", .{ name, suffix }) });
        const run = b.addSystemCommand(&.{
            "dotnet",  "run",    b.pathJoin(&.{ ctx.root, "scripts/compile_slang.cs" }),
            "--slangc", ctx.slangc_exe,
            "--raw",    "--target",                                                 "wgsl",
            "--entry",  entry,                                                      "--stage", stage,
        });
        run.step.dependOn(ctx.slang_step);
        for (includes) |inc| run.addArgs(&.{ "--include", inc });
        run.addArgs(&.{ "--input", input, "--output", out_file });
        run.setName(b.fmt("compile {s}.{s}.wgsl", .{ name, suffix }));
        return run;
    }

    /// Compiles every authored material × `pass`, mirroring
    /// cmake/CompileMaterialShaders.cmake's ke_compile_material_shaders: glob
    /// every materials directory (globbing happens right here, synchronously,
    /// during graph construction — the same moment CMake's CONFIGURE_DEPENDS
    /// glob ran), generate a wrapper binding each material into the pass's
    /// entry points, then compile the wrapper like any other pass shader. The
    /// wrapper `import`s the material by module name, so every materials dir
    /// must be on the compile include path alongside the pass's own.
    fn materialShaders(
        ctx: *Ctx,
        pass: []const u8,
        template: []const u8,
        includes: []const []const u8,
        out_dir: []const u8,
        materials_dirs: []const []const u8,
    ) []const *std.Build.Step.Run {
        const b = ctx.b;
        var steps: std.ArrayList(*std.Build.Step.Run) = .empty;
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
                    "dotnet",     "run", b.pathJoin(&.{ ctx.root, "scripts/generate_material_wrapper.cs" }),
                    "--material", material_path,
                    "--template", template,
                    "--output",   wrapper,
                });
                gen_wrapper.setName(b.fmt("generate {s} wrapper", .{combined_name}));

                const vs = ctx.shader(combined_name, "vertex", "vs_main", wrapper, out_dir, wrapper_includes.items);
                vs.step.dependOn(&gen_wrapper.step);
                const fs = ctx.shader(combined_name, "fragment", "fs_main", wrapper, out_dir, wrapper_includes.items);
                fs.step.dependOn(&gen_wrapper.step);

                steps.append(b.allocator, vs) catch @panic("OOM");
                steps.append(b.allocator, fs) catch @panic("OOM");
            }
        }
        return steps.toOwnedSlice(b.allocator) catch @panic("OOM");
    }

    /// Invokes `zig build --prefix <shared prefix> <extra args>` in `dir`,
    /// mirroring exactly what each plugin's CMakeLists.txt custom command used
    /// to do. Every plugin's own build.zig already installs its .so to "lib"
    /// under whatever --prefix it's given, so pointing every invocation at the
    /// SAME shared prefix makes them all land in one directory — no
    /// zig-out-then-copy indirection needed (that dance existed only to work
    /// around a CMake quirk, not a Zig one).
    fn plugin(ctx: *Ctx, name: []const u8, dir: []const u8, extra_args: []const []const u8, deps: []const *std.Build.Step) *std.Build.Step.Run {
        const b = ctx.b;
        const run = b.addSystemCommand(&.{ ctx.zig_exe, "build", "--prefix", ctx.prefix });
        run.addArgs(extra_args);
        run.addArg(ctx.release_flag);
        if (ctx.target_arg.len != 0) run.addArg(ctx.target_arg);
        run.setCwd(.{ .cwd_relative = b.pathJoin(&.{ b.build_root.path.?, dir }) });
        run.step.dependOn(ctx.vcpkg_step);
        for (deps) |d| run.step.dependOn(d);
        run.setName(b.fmt("build {s} (Zig)", .{name}));
        return run;
    }

    /// Like `plugin`, but for a C example: every example's own build.zig
    /// hardcodes its exe name to "demo" and installs to "bin" under whatever
    /// --prefix it's given, so pointing several examples at the shared
    /// engine prefix would make each one overwrite the last one's binary.
    /// Each example instead gets its own private sub-prefix, then the
    /// resulting "demo" binary is copied into the shared prefix's bin/ under
    /// its own name — mirroring the exact two-path pattern CMake used to
    /// dodge its IMPORTED_LOCATION collision bug, applied here to dodge an
    /// install-path collision instead.
    fn example(ctx: *Ctx, demo_name: []const u8, dir: []const u8, extra_args: []const []const u8, deps: []const *std.Build.Step) *std.Build.Step.Run {
        const b = ctx.b;
        const own_prefix = b.pathJoin(&.{ ctx.prefix, "examples-out", demo_name });
        const run = b.addSystemCommand(&.{ ctx.zig_exe, "build", "--prefix", own_prefix });
        run.addArgs(extra_args);
        run.addArg(ctx.release_flag);
        if (ctx.target_arg.len != 0) run.addArg(ctx.target_arg);
        run.setCwd(.{ .cwd_relative = b.pathJoin(&.{ b.build_root.path.?, dir }) });
        run.step.dependOn(ctx.vcpkg_step);
        for (deps) |d| run.step.dependOn(d);
        run.setName(b.fmt("build {s} (Zig)", .{demo_name}));

        const copy = b.addSystemCommand(&.{
            "install", "-Dm755",
            b.pathJoin(&.{ own_prefix, "bin", "demo" }),
            b.pathJoin(&.{ ctx.prefix, "bin", demo_name }),
        });
        copy.step.dependOn(&run.step);
        copy.setName(b.fmt("install {s}", .{demo_name}));
        return copy;
    }

    /// Invokes a GTest suite's own build.zig, which shells out to the SYSTEM
    /// C++ compiler directly (not `zig build`'s usual target/prefix machinery
    /// — Zig's bundled libc++ is ABI-incompatible with vcpkg's libstdc++-built
    /// GTest archives). No --prefix/--release forwarded: the suite's build.zig
    /// declares no such options, it just writes straight to -Doutput.
    fn testBinary(ctx: *Ctx, name: []const u8, dir: []const u8, extra_args: []const []const u8, deps: []const *std.Build.Step) *std.Build.Step.Run {
        const b = ctx.b;
        const run = b.addSystemCommand(&.{ ctx.zig_exe, "build" });
        run.addArgs(extra_args);
        run.setCwd(.{ .cwd_relative = b.pathJoin(&.{ b.build_root.path.?, dir }) });
        run.step.dependOn(ctx.vcpkg_step);
        for (deps) |d| run.step.dependOn(d);
        run.setName(b.fmt("build {s} (system C++)", .{name}));
        return run;
    }
};

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

/// Compiler for the two GTest suites' link step: must match vcpkg's GTest,
/// built with `zig c++` (vcpkg-triplets/x64-{windows,linux}-zig.cmake).
fn testCxxArgs(b: *std.Build, target: std.Build.ResolvedTarget, root: []const u8) []const []const u8 {
    const shim = if (target.result.os.tag == .windows) "zig-cxx.cmd" else "zig-cxx.sh";
    return &.{argF(b, "cxx", b.pathJoin(&.{ root, "vcpkg-triplets", shim }))};
}

fn argF(b: *std.Build, comptime name: []const u8, value: []const u8) []const u8 {
    return b.fmt("-D" ++ name ++ "={s}", .{value});
}
