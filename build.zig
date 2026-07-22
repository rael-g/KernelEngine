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
    const vcpkg_root = b.option([]const u8, "vcpkg-root", "path to the vcpkg checkout") orelse
        b.graph.environ_map.get("VCPKG_ROOT") orelse
        @panic("VCPKG_ROOT not set; pass -Dvcpkg-root=<path> or export VCPKG_ROOT");

    const triplet = switch (target.result.os.tag) {
        .windows => "x64-windows-static-md",
        else => "x64-linux",
    };

    // ── vcpkg (manifest mode) ────────────────────────────────────────────────
    const vcpkg_installed = b.pathJoin(&.{ root, "vcpkg_installed_zig" });
    const vcpkg_exe = b.pathJoin(&.{ vcpkg_root, if (target.result.os.tag == .windows) "vcpkg.exe" else "vcpkg" });
    const vcpkg_install = b.addSystemCommand(&.{
        vcpkg_exe,
        "install",
        b.fmt("--triplet={s}", .{triplet}),
        b.fmt("--x-manifest-root={s}", .{root}),
        b.fmt("--x-install-root={s}", .{vcpkg_installed}),
    });

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
    const cxx_runtime = findCxxRuntime(b);

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
    };

    // ── kernel built-ins ─────────────────────────────────────────────────────
    const common = ctx.plugin("ke_common", "src/zig/common", &.{}, &.{});

    const logger_simple = ctx.plugin("ke_logger_simple", "src/zig/logger/simple", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger/include" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const ecs_flecs = ctx.plugin("ke_ecs_flecs", "src/zig/ecs/flecs", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs/include" })),
        argF(b, "flecs-include", vcpkg_include),
        argF(b, "flecs-lib", b.pathJoin(&.{ vcpkg_lib, "libflecs_static.a" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const input_default = ctx.plugin("ke_input_default", "src/zig/input/default", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-input-include", b.pathJoin(&.{ src_c, "input/include" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const resource_cache_default = ctx.plugin("ke_resource_cache_default", "src/zig/resource_cache/default", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-resource-cache-include", b.pathJoin(&.{ src_c, "resource_cache/include" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const scheduler_enki = ctx.plugin("ke_scheduler_enki", "src/zig/scheduler/enki", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler/include" })),
        argF(b, "enki-include", b.pathJoin(&.{ vcpkg_include, "enkiTS" })),
        argF(b, "enki-lib", vcpkg_lib),
        argF(b, "kerror-src", kerror_src),
        argF(b, "cxx-runtime", cxx_runtime),
    }, &.{});

    const runtime = ctx.plugin("ke_runtime", "src/zig/runtime", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs/include" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler/include" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime/include" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const framework = ctx.plugin("ke_framework", "src/zig/framework", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs/include" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial/include" })),
        argF(b, "ke-input-include", b.pathJoin(&.{ src_c, "input/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render/include" })),
        argF(b, "ke-asset-include", b.pathJoin(&.{ src_c, "asset/include" })),
        argF(b, "ke-text-include", b.pathJoin(&.{ src_c, "text/include" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime/include" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler/include" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const window_glfw = ctx.plugin("ke_window_glfw", "src/zig/window/glfw", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-window-include", b.pathJoin(&.{ src_c, "window/include" })),
        argF(b, "ke-input-include", b.pathJoin(&.{ src_c, "input/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger/include" })),
        argF(b, "glfw-include", vcpkg_include),
        argF(b, "glfw-lib", vcpkg_lib),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const asset_stb_image = ctx.plugin("ke_asset_stb_image", "src/zig/asset/stb_image", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render/include" })),
        argF(b, "ke-asset-include", b.pathJoin(&.{ src_c, "asset/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "asset/stb_image/include" })),
        argF(b, "stb-include", vcpkg_include),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const audio_miniaudio = ctx.plugin("ke_audio_miniaudio", "src/zig/audio/miniaudio", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger/include" })),
        argF(b, "ke-audio-include", b.pathJoin(&.{ src_c, "audio/include" })),
        argF(b, "ke-resource-cache-include", b.pathJoin(&.{ src_c, "resource_cache/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "audio/miniaudio/include" })),
        argF(b, "miniaudio-include", vcpkg_include),
        argF(b, "ke-resource-cache-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{&resource_cache_default.step});

    const text_stb_truetype = ctx.plugin("ke_text_stb_truetype", "src/zig/text/stb_truetype", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger/include" })),
        argF(b, "ke-text-include", b.pathJoin(&.{ src_c, "text/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "text/stb_truetype/include" })),
        argF(b, "stb-include", vcpkg_include),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const physics_box2d = ctx.plugin("ke_physics_2d_box2d", "src/zig/physics/box2d", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-physics-include", b.pathJoin(&.{ src_c, "physics/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger/include" })),
        argF(b, "box2d-include", vcpkg_include),
        argF(b, "box2d-lib", b.pathJoin(&.{ vcpkg_lib, if (debug) "libbox2dd.a" else "libbox2d.a" })),
        argF(b, "kerror-src", kerror_src),
    }, &.{});

    const assimp_libs = b.fmt("{s}|{s}|{s}|{s}|{s}|{s}", .{
        b.pathJoin(&.{ vcpkg_lib, if (debug) "libassimpd.a" else "libassimp.a" }),
        b.pathJoin(&.{ vcpkg_lib, "libpolyclipping.a" }),
        b.pathJoin(&.{ vcpkg_lib, "libpoly2tri.a" }),
        b.pathJoin(&.{ vcpkg_lib, "libpugixml.a" }),
        b.pathJoin(&.{ vcpkg_lib_release, "libz.a" }),
        b.pathJoin(&.{ vcpkg_lib, "libminizip.a" }),
    });
    const asset_assimp = ctx.plugin("ke_asset_assimp", "src/zig/asset/assimp", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-asset-include", b.pathJoin(&.{ src_c, "asset/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render/include" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler/include" })),
        argF(b, "assimp-include", vcpkg_include),
        argF(b, "assimp-libs", assimp_libs),
        argF(b, "stb-include", vcpkg_include),
        argF(b, "kerror-src", kerror_src),
        argF(b, "cxx-runtime", cxx_runtime),
    }, &.{});

    const configuration = ctx.plugin("ke_configuration", "src/zig/configuration", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-config-include", b.pathJoin(&.{ src_c, "configuration/include" })),
        argF(b, "ke-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
    }, &.{&common.step});

    const configuration_toml = ctx.plugin("ke_configuration_toml", "src/zig/configuration/toml", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-config-include", b.pathJoin(&.{ src_c, "configuration/include" })),
        argF(b, "ke-lib-dir", b.pathJoin(&.{ ctx.prefix, "lib" })),
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
    const wgpu_marker = b.pathJoin(&.{ wgpu_dir, "lib", "libwgpu_native.so" });
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
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render/include" })),
        argF(b, "ke-window-include", b.pathJoin(&.{ src_c, "window/include" })),
        argF(b, "ke-scheduler-include", b.pathJoin(&.{ src_c, "scheduler/include" })),
        argF(b, "wgpu-include", wgpu_include),
        argF(b, "wgpu-lib", wgpu_lib_dir),
    }, &.{ &common.step, &wgpu_fetch.step });

    // wgpu-native is linked dynamically: every consumer needs its .so beside
    // them at runtime. Copied into the shared lib dir once, here, rather than
    // every consumer computing its own rpath into the .cache tree.
    const wgpu_copy = b.addSystemCommand(&.{
        "cp", "-f",
        b.pathJoin(&.{ wgpu_lib_dir, "libwgpu_native.so" }),
        b.pathJoin(&.{ ctx.prefix, "lib", "libwgpu_native.so" }),
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
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger/include" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/tonemap/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &tonemap_vs.step, &tonemap_fs.step });

    const skybox_vs = ctx.shader("skybox", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/skybox/shaders/skybox.slang" }), shaders_out, &.{});
    const skybox_fs = ctx.shader("skybox", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/skybox/shaders/skybox.slang" }), shaders_out, &.{});
    const skybox = ctx.plugin("ke_render_skybox", "src/zig/render/skybox", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs/include" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime/include" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/skybox/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step, &skybox_vs.step, &skybox_fs.step });

    const ui_vs = ctx.shader("ui", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/ui/shaders/ui.slang" }), shaders_out, &.{});
    const ui_fs = ctx.shader("ui", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/ui/shaders/ui.slang" }), shaders_out, &.{});
    const ui = ctx.plugin("ke_render_ui", "src/zig/render/ui", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs/include" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/ui/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step, &ui_vs.step, &ui_fs.step });

    const shadow_vs = ctx.shader("shadow", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/shadow/shaders/shadow.slang" }), shaders_out, &.{});
    const shadow_fs = ctx.shader("shadow", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/shadow/shaders/shadow.slang" }), shaders_out, &.{});
    const shadow = ctx.plugin("ke_render_shadow", "src/zig/render/shadow", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs/include" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime/include" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/shadow/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step, &shadow_vs.step, &shadow_fs.step });

    const cluster_cs = ctx.shader("cluster_cull", "compute", "cs_main", b.pathJoin(&.{ src_zig, "render/cluster/shaders/cluster_cull.slang" }), shaders_out, &.{});
    const cluster = ctx.plugin("ke_render_cluster", "src/zig/render/cluster", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs/include" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime/include" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/cluster/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step, &cluster_cs.step });

    const dl_includes = [_][]const u8{ shader_lib_dir, b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders" }) };
    const deferred_lighting_vs = ctx.shader("deferred_lighting", "vertex", "vs_main", b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders/deferred_lighting.slang" }), shaders_out, &dl_includes);
    const deferred_lighting_fs = ctx.shader("deferred_lighting", "fragment", "fs_main", b.pathJoin(&.{ src_zig, "render/deferred_lighting/shaders/deferred_lighting.slang" }), shaders_out, &dl_includes);
    const deferred_lighting = ctx.plugin("ke_render_deferred_lighting", "src/zig/render/deferred_lighting", &.{
        argF(b, "ke-common-include", b.pathJoin(&.{ src_zig, "common/include" })),
        argF(b, "ke-ecs-include", b.pathJoin(&.{ src_c, "ecs/include" })),
        argF(b, "ke-runtime-include", b.pathJoin(&.{ src_c, "runtime/include" })),
        argF(b, "ke-spatial-include", b.pathJoin(&.{ src_c, "spatial/include" })),
        argF(b, "ke-render-include", b.pathJoin(&.{ src_c, "render/include" })),
        argF(b, "ke-logger-include", b.pathJoin(&.{ src_c, "logger/include" })),
        argF(b, "ke-self-include", b.pathJoin(&.{ src_zig, "render/deferred_lighting/include" })),
        argF(b, "ke-lib-dir", lib_dir),
    }, &.{ &common.step, &runtime.step, &deferred_lighting_vs.step, &deferred_lighting_fs.step });

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
        cluster,         deferred_lighting, gpu_device_webgpu,
    };
    for (all_plugins) |p| b.getInstallStep().dependOn(&p.step);
    b.getInstallStep().dependOn(&wgpu_copy.step);

    // ── one example, end to end, no CMake anywhere in the chain ─────────────
    const demo01 = b.addSystemCommand(&.{
        ctx.zig_exe, "build",
        "--prefix", ctx.prefix,
        b.fmt("-Dinclude-dirs={s}|{s}", .{
            b.pathJoin(&.{ src_c, "logger/include" }),
            b.pathJoin(&.{ src_zig, "common/include" }),
        }),
        b.fmt("-Dlibs={s}", .{b.pathJoin(&.{ lib_dir, "libke_logger_simple.so" })}),
    });
    demo01.setCwd(.{ .cwd_relative = b.pathJoin(&.{ root, "examples/c/01_minimal_log" }) });
    demo01.step.dependOn(&logger_simple.step);

    const demo_step = b.step("demo01", "Build examples/c/01_minimal_log with zero CMake involved");
    demo_step.dependOn(&demo01.step);
}

const Ctx = struct {
    b: *std.Build,
    root: []const u8,
    zig_exe: []const u8,
    prefix: []const u8,
    release_flag: []const u8,
    vcpkg_step: *std.Build.Step,

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
            "python3", b.pathJoin(&.{ ctx.root, "scripts/compile_slang.py" }),
            "--raw",   "--target",                                          "wgsl",
            "--entry", entry,                                                "--stage", stage,
        });
        for (includes) |inc| run.addArgs(&.{ "--include", inc });
        run.addArgs(&.{ "--input", input, "--output", out_file });
        run.setName(b.fmt("compile {s}.{s}.wgsl", .{ name, suffix }));
        return run;
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
        run.setCwd(.{ .cwd_relative = b.pathJoin(&.{ b.build_root.path.?, dir }) });
        run.step.dependOn(ctx.vcpkg_step);
        for (deps) |d| run.step.dependOn(d);
        run.setName(b.fmt("build {s} (Zig)", .{name}));
        return run;
    }
};

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
