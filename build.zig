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
    const vcpkg_root = b.option([]const u8, "vcpkg-root", "path to the vcpkg checkout") orelse
        b.graph.environ_map.get("VCPKG_ROOT") orelse
        @panic("VCPKG_ROOT not set; pass -Dvcpkg-root=<path> or export VCPKG_ROOT");

    // Windows equivalent of x64-linux — same shape (dynamic CRT, static lib
    // linkage), built with `zig cc`/`zig c++` (vcpkg-triplets/x64-windows-zig.cmake)
    // instead of MSVC, so no Visual Studio / Windows SDK install is required.
    // See ZigMigrationPlan.md §3 risk 1: this is the "preferred" GNU/mingw
    // road, validated against glfw3 + assimp (the heaviest C++ port).
    const triplet = switch (target.result.os.tag) {
        .windows => "x64-windows-zig",
        else => "x64-linux",
    };

    // ── vcpkg (manifest mode) ────────────────────────────────────────────────
    const vcpkg_installed = b.pathJoin(&.{ root, "vcpkg_installed_zig" });
    const vcpkg_exe = b.pathJoin(&.{ vcpkg_root, if (target.result.os.tag == .windows) "vcpkg.exe" else "vcpkg" });
    const vcpkg_overlay_triplets = b.pathJoin(&.{ root, "vcpkg-triplets" });
    var vcpkg_install_args: std.ArrayList([]const u8) = .empty;
    vcpkg_install_args.appendSlice(b.allocator, &.{
        vcpkg_exe,
        "install",
        b.fmt("--triplet={s}", .{triplet}),
        b.fmt("--x-manifest-root={s}", .{root}),
        b.fmt("--x-install-root={s}", .{vcpkg_installed}),
    }) catch @panic("OOM");
    if (target.result.os.tag == .windows) {
        vcpkg_install_args.appendSlice(b.allocator, &.{
            b.fmt("--overlay-triplets={s}", .{vcpkg_overlay_triplets}),
            b.fmt("--host-triplet={s}", .{triplet}),
        }) catch @panic("OOM");
    }
    const vcpkg_install = b.addSystemCommand(vcpkg_install_args.items);

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
    // MSVC pulls its C++ runtime in implicitly through the import libraries
    // (enkiTS's/Assimp's own .lib), so there's nothing to resolve on Windows —
    // only ELF/libstdc++ toolchains need this probe.
    const cxx_runtime = if (target.result.os.tag == .windows) null else findCxxRuntime(b);

    // Absolute, always: each plugin's `zig build` runs with its OWN directory
    // as cwd, so a relative --prefix here would resolve against the wrong
    // place there.
    const absolute_prefix = if (std.fs.path.isAbsolute(b.install_prefix))
        b.install_prefix
    else
        b.pathJoin(&.{ root, b.install_prefix });

    var ctx = Ctx{
        .b = b,
        .root = root,
        .zig_exe = b.graph.zig_exe,
        .prefix = absolute_prefix,
        .release_flag = if (debug) "--release=off" else "--release=fast",
        .vcpkg_step = &vcpkg_install.step,
        // Windows' python.org installer provides "python", not "python3" —
        // and the Store's "python3" app-execution-alias stub, which shadows
        // it on PATH, only prints an install nag and never runs anything.
        .python_exe = if (target.result.os.tag == .windows) "python" else "python3",
        .target_arg = if (target.result.os.tag == .windows) "-Dtarget=x86_64-windows-gnu" else "",
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

    const scheduler_enki = ctx.plugin("ke_scheduler_enki", "src/zig/scheduler/enki", std.mem.concat(b.allocator, []const u8, &.{
        &.{
            argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
            argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
            argF(b, "enki-include", b.pathJoin(&.{ vcpkg_include, "enkiTS" })),
            argF(b, "enki-lib", vcpkg_lib),
            argF(b, "kerror-src", kerror_src),
        },
        cxxRuntimeArgs(b, cxx_runtime),
    }) catch @panic("OOM"), &.{});

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
    const asset_assimp = ctx.plugin("ke_asset_assimp", "src/zig/asset/assimp", std.mem.concat(b.allocator, []const u8, &.{
        &.{
            argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
            argF(b, "ke-asset-include", b.pathJoin(&.{ src_c, "asset" })),
            argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
            argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
            argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler" })),
            argF(b, "assimp-include", vcpkg_include),
            argF(b, "assimp-libs", assimp_libs),
            argF(b, "stb-include", vcpkg_include),
            argF(b, "kerror-src", kerror_src),
        },
        cxxRuntimeArgs(b, cxx_runtime),
    }) catch @panic("OOM"), &.{});

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
    // per-(material,pass) wrapper via generate_material_wrapper.py, then
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

    // ke_render_core: the forward-renderer aggregator. Its @embedFile of the
    // magenta fallback shader means those two WGSL files must exist on disk
    // BEFORE core's own `zig build` starts — a harder ordering constraint than
    // a normal link dependency, so the compile steps are threaded into core's
    // deps explicitly rather than relying on the shared shaders_out directory
    // existing by coincidence.
    const core_gen_dir = b.pathJoin(&.{ ctx.prefix, "gen", "render_core" });
    const magenta_slang = b.pathJoin(&.{ src_zig, "render/core/shaders/magenta.slang" });
    const magenta_vs = ctx.shader("magenta", "vertex", "vs_main", magenta_slang, core_gen_dir, &.{});
    const magenta_fs = ctx.shader("magenta", "fragment", "fs_main", magenta_slang, core_gen_dir, &.{});
    const magenta_vs_wgsl = b.pathJoin(&.{ core_gen_dir, "magenta.vs.wgsl" });
    const magenta_fs_wgsl = b.pathJoin(&.{ core_gen_dir, "magenta.fs.wgsl" });

    const render_core = ctx.plugin("ke_render_core", "src/zig/render/core", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render" })),
        argF(b, "ke-resource-cache-include", b.pathJoin(&.{ src_c, "resource_cache" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/core/include" })),
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
        forward,         render_core,
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

    // glslangValidator (unlike compile_slang.py) never creates its own output
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

    const demo12 = ctx.example("c_demo_12", "examples/c/12_render_core", &.{
        argF(b, "python", ctx.python_exe),
        argF(b, "compile-slang", b.pathJoin(&.{ root, "scripts/compile_slang.py" })),
        argF(b, "shader-out-dir", b.pathJoin(&.{ examples_gen, "12_render_core" })),
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_zig, "render/core/include" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_core") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
        })),
    }, &.{ &common.step, &window_glfw.step, &gpu_device_webgpu.step, &render_core.step, &ecs_flecs.step });

    const demo13 = ctx.example("c_demo_13", "examples/c/13_runtime_clear", &.{
        argF(b, "include-dirs", joinPaths(b, &.{
            b.pathJoin(&.{ src_c, "window" }),
            b.pathJoin(&.{ src_c, "ecs" }),
            b.pathJoin(&.{ src_c, "scheduler" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
            b.pathJoin(&.{ src_zig, "window/glfw/include" }),
            b.pathJoin(&.{ src_zig, "render/webgpu/include" }),
            b.pathJoin(&.{ src_c, "render" }),
            b.pathJoin(&.{ src_zig, "render/core/include" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
            b.pathJoin(&.{ src_zig, "scheduler/enki/include" }),
            b.pathJoin(&.{ src_c, "runtime" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_core") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
        })),
    }, &.{
        &common.step,     &window_glfw.step, &gpu_device_webgpu.step, &render_core.step,
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
            b.pathJoin(&.{ src_zig, "render/core/include" }),
            b.pathJoin(&.{ src_zig, "ecs/flecs/include" }),
            b.pathJoin(&.{ src_zig, "scheduler/enki/include" }),
            b.pathJoin(&.{ src_c, "runtime" }),
        })),
        argF(b, "libs", joinPaths(b, &.{
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_common") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_window_glfw") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_gpu_device_webgpu") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_render_core") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_ecs_flecs") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_scheduler_enki") }),
            b.pathJoin(&.{ lib_dir, libFileName(b, target, "ke_runtime") }),
        })),
        "-Dlink-m=true",
    }, &.{
        &common.step,     &window_glfw.step, &gpu_device_webgpu.step, &render_core.step,
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
    python_exe: []const u8,
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

    /// Compiles one Slang entry point to WGSL via scripts/compile_slang.py,
    /// mirroring cmake/CompileSlangShader.cmake's ke_compile_slang_shader.
    /// Every render pass loads its shaders at runtime by logical name via
    /// ke_render_core::load_shader, so the output always lands in the one
    /// shared runtime shaders directory, never embedded in a plugin's own .so
    /// (render/core's own embedded fallback shader is the one exception —
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
            ctx.python_exe, b.pathJoin(&.{ ctx.root, "scripts/compile_slang.py" }),
            "--raw",         "--target",                                          "wgsl",
            "--entry",       entry,                                                "--stage", stage,
        });
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
                    ctx.python_exe, b.pathJoin(&.{ ctx.root, "scripts/generate_material_wrapper.py" }),
                    "--material",   material_path,
                    "--template",   template,
                    "--output",     wrapper,
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

/// enkiTS's and Assimp's own build.zig treat `-Dcxx-runtime` as optional —
/// absent on toolchains (MSVC) where the C++ runtime comes in implicitly
/// through the import library. Omit the flag entirely rather than pass an
/// empty path.
fn cxxRuntimeArgs(b: *std.Build, cxx_runtime: ?[]const u8) []const []const u8 {
    const path = cxx_runtime orelse return &.{};
    return &.{argF(b, "cxx-runtime", path)};
}

/// The GTest suites default to inlining "clang++" (a system compiler, matching
/// the vcpkg-built GTest archives' toolchain — see tests/c/kernel/build.zig).
/// On Windows there is no standalone clang++ on PATH, and vcpkg's GTest was
/// itself built with `zig c++` (vcpkg-triplets/x64-windows-zig.cmake), so the
/// matching compiler for this link step is the same zig-cxx.cmd shim.
fn testCxxArgs(b: *std.Build, target: std.Build.ResolvedTarget, root: []const u8) []const []const u8 {
    if (target.result.os.tag != .windows) return &.{};
    return &.{argF(b, "cxx", b.pathJoin(&.{ root, "vcpkg-triplets", "zig-cxx.cmd" }))};
}

fn argF(b: *std.Build, comptime name: []const u8, value: []const u8) []const u8 {
    return b.fmt("-D" ++ name ++ "={s}", .{value});
}

/// Finds the system C++ runtime .so the same way every plugin's CMakeLists
/// used to (find_library over CMAKE_CXX_IMPLICIT_LINK_DIRECTORIES) — here via
/// the C++ compiler's own -print-file-name, since there's no CMake toolchain
/// probe to ask anymore. Needs the compiler's fully-qualified path: run
/// through a bare name ("c++"), gcc/clang can't determine their own install
/// prefix and silently echo the request back unresolved instead of erroring
/// (verified: -print-file-name only resolves when argv[0] is absolute).
fn findCxxRuntime(b: *std.Build) []const u8 {
    var threaded: std.Io.Threaded = .init(b.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const candidates = [_][]const u8{ "/usr/bin/c++", "/usr/bin/g++", "/usr/bin/clang++" };
    for (candidates) |cxx| {
        const result = std.process.run(b.allocator, io, .{
            .argv = &.{ cxx, "-print-file-name=libstdc++.so" },
        }) catch continue;
        const trimmed = std.mem.trimEnd(u8, result.stdout, "\n \t");
        if (std.fs.path.isAbsolute(trimmed)) return trimmed;
    }
    @panic("could not resolve libstdc++.so via any known system C++ compiler path");
}
