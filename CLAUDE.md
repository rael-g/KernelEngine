# KernelEngine

A microkernel game engine: a small ABI-stable C kernel surrounded by C++ plugin backends and a managed C# layer for game code.

> **Branch state — single source of truth for in-flight work**: see [`docs/RuntimeArchitectureV2.md`](docs/RuntimeArchitectureV2.md) §17.6 (execution log + current tree state + next phases). This file describes the engine doctrine and conventions; the runtime architecture doc describes what's been built and what's next.

---

## Build

### Native (Zig + vcpkg manifest mode)

CMake is gone. The root `build.zig` is the only native build orchestrator: it resolves vcpkg directly (manifest mode — `vcpkg.json` + `vcpkg-configuration.json`, no toolchain file), then invokes every plugin's own `build.zig` with one shared `--prefix` so every `.so`/`.dll` converges into one output directory. Each plugin still owns its own `build.zig`, callable standalone the same way (see any `src/zig/<plugin>/build.zig` header comment for its options).

vcpkg itself is fetched automatically (`.cache/vcpkg-<version>/`) — no manual install, no `VCPKG_ROOT` needed. Pass `-Dvcpkg-root=<path>` (or export `VCPKG_ROOT`) only to point at an existing vcpkg checkout instead.

```bash
zig build --prefix build/native                     # configure + build + install, one step
build/native/bin/c_demo_01                           # run a C example (Linux name; c_demo_01.exe on Windows)
build/native/bin/test_ke_kernel                      # native kernel/framework tests (GTest)
build/native/bin/test_integration_cpp                # native integration tests (GTest)
```

Build output converges entirely under the given `--prefix` (e.g. `build/native/{bin,lib}/`) — no separate install step, and no build/CMake-preset directory split between "configure" and "install" locations. C# expects native libraries at `build/native/bin/`.

**`test_ke_kernel` and `test_integration_cpp` (C++/GTest) are frozen — new tests are written in Zig, not C++.** They exist only because they predate the engine's move to Zig; keep them passing, but grow them only as a byproduct of touching that file for another reason, never to house new coverage. A new test for Zig-implemented engine logic belongs in that plugin's own `zig build test` (see any `src/zig/<plugin>/build.zig` for the pattern — `b.addTest` against the plugin's own source, run via `b.addRunArtifact`).

### Managed (.NET 10)

```bash
dotnet build
dotnet test KernelEngine.slnx
```

### Scripts

```bash
dotnet run scripts/compile_slang.cs   # compile a render-v2 .slang shader to WGSL (see root build.zig's Ctx.shader/materialShaders helpers for the driven build)
dotnet run scripts/generate_bindings.cs  # regenerate all C# P/Invoke bindings via ClangSharp
dotnet run scripts/coverage.cs        # C# test coverage report, C# only (clean | report subcommands)
```

Shaders compile to `src/zig/render/core/shaders/` (`.slang` sources) → generated WGSL under the Zig build's shader-gen directory, embedded into `ke_render_core` via `@embedFile`. Binding regen runs `dotnet tool restore` from `src/csharp/` first, then processes every `.rsp` under `src/csharp/Native/`.

**Known debt — no native/Zig coverage story.** `scripts/coverage.cs` only measures C#. Zig's own compiler has no source-coverage instrumentation. DWARF-based tools don't fill the gap either: `kcov` (which works via `libdw`, compiler-agnostic in principle) was tried directly against a Zig-compiled binary and produces silent 0% coverage — Zig 0.16 emits a line-table extended opcode `libdw` doesn't decode, confirmed by comparing against an identical `gcc`/`zig cc`-compiled C binary (which `kcov` measures correctly) and by inspecting the raw DWARF with `readelf --debug-dump=decodedline`. This blocks coverage for both `zig build test` targets and the two legacy GTest suites equally, so there's no coverage-driven reason to keep writing new tests in C++.

### Running examples after a native rebuild

Never pass `--no-build` to `dotnet run` after a `zig build`. The native DLL copy step (a `PreserveNewest` item in `NativeDependencies.targets`) runs only during a build; `dotnet run --no-build` silently keeps the stale DLL already in `bin/Debug/net10.0/` and runs the old C++. Always use `dotnet run` / `dotnet build` (no `--no-build`); the timestamp-based copy then refreshes the native side automatically.

---

## Architecture — four layers

```
Layer 4 — C# managed (src/csharp/)          Game code, opinionated framework, wrappers
Layer 3 — C# native bindings (.../Native/)  ClangSharp-generated P/Invoke
Layer 2 — C++ plugins (src/cpp/, src/c/ecs/flecs, src/c/runtime, src/c/framework)
Layer 1 — C kernel (src/c/kernel/)          ABI-stable contracts (vtables)
```

### Layer 1 — C kernel (`src/c/kernel/`)

Pure C, ABI-stable (`extern "C"`). All public surface is vtable-shaped (struct of function pointers). Public headers under `include/kernel_engine/kernel/<domain>/`; private impl under `src/<domain>/`.

Stable types:
- `ke_logger` / `ke_logger_sink` — pluggable logging
- `ke_ecs` — language-agnostic ECS contract (entity lifetime + component storage + query). One implementation today: `KernelEngine.Ecs.Flecs` (flecs as storage-only, pipeline addons stripped).
- `ke_runtime` — scheduler contract (phase loop + parallel waves + defer queue + fixed timestep). One implementation: in-house Bevy-style scheduler at `src/c/runtime/`.
- `ke_system_ctx` — the only doorway to component memory inside a system body (R2.5c safety doctrine; see `docs/RuntimeArchitectureV2.md` §15).
- `ke_render` / `ke_window` — vtable interfaces for renderer and window backends.
- `ke_task_scheduler` — single shared worker pool (enkiTS impl) used by every parallel subsystem.
- `ke_resource_cache` — generic refcount + path-keyed dedup primitive, kernel built-in (`src/c/kernel/src/resource_cache/`).

No `ke_kernel` meta-target: consumers link specific domain impl `.so`s directly (e.g. `ke_logger_simple`, `ke_resource_cache_default`).

### Layer 2 — Plugins

Each plugin is a shared library that exports **exactly one symbol per factory header** — the create function. Everything else the plugin exposes is a vtable returned by that factory.

Active plugins:
- `src/c/runtime/` → `ke_runtime_create` — scheduler
- `src/c/ecs/flecs/` → `ke_ecs_flecs_create` — flecs-backed storage
- `src/c/framework/` → `ke_world_create`, `ke_asset_resolver_create`, `ke_scene_tree_create`, `ke_scene_loader_create`, `ke_input_actions_create` — the engine's opinionated composition layer (vocabulary + scene file format + lifecycle aggregator)
- `src/zig/render/core/` + `src/zig/render/webgpu/` → `ke_render_core_create` / `ke_gpu_device_webgpu_create` — the render-v2 forward renderer (WebGPU via wgpu-native). The only renderer; the legacy bgfx backend was removed once every example had migrated (see `docs/RenderArchitectureV2.md`).
- `src/cpp/window/glfw/` → `ke_window_glfw_create` — GLFW window
- `src/cpp/asset/assimp/`, `src/cpp/asset/stb_image/` — asset loaders
- `src/cpp/task_scheduler/enki/` → `ke_task_scheduler_enki_create` — enkiTS worker pool
- `src/cpp/audio/miniaudio/`, `src/cpp/physics/box2d/`, `src/cpp/text/stb_truetype/` — domain backends

Plugin vendoring rule: when vcpkg lacks a pure-C library, vendor it inside `src/c/<plugin>/third_party/<lib>/` with a `VENDOR.md` recording upstream + license + sync date. Contained — never leaks to kernel or sibling plugins. Established precedent: tomlc99 inside `src/c/framework/third_party/tomlc99/`.

#### Layer boundary rule (non-negotiable)

- `src/c/kernel/include/` is the **sole** source of public engine API. Every interface, vtable, struct, enum, and function the engine exposes lives here. C ABI only.
- Each plugin (`src/c/<plugin>/`, `src/cpp/<plugin>/`) exposes exactly **one factory per factory header** in `<plugin>/include/kernel_engine/<domain>/[<plugin>/]<name>_create.h`. Everything else is implementation detail (`.hpp` / `.c` / `.cpp` files under `src/`).
- Plugin contract headers declare vtable shapes **only** — no `KE_*_API` export macros, no plain function decls. Exports live exclusively in the impl-side `_create.h` files. Domain-only contract dirs (no implementation left in them, fully migrated to Zig plugins elsewhere) live at `src/c/<domain>/kernel_engine/<domain>/*.h` — one `-I src/c/<domain>` per domain, so a consumer only sees the domains it explicitly asked for (want `scheduler`? include `scheduler`).
- If a "generic utility" feels like it wants to live in a plugin's public header, it belongs in `src/c/kernel/` instead. Implement in C (use C11 `_Thread_local`, etc., not C++).

### Layer 3 — C# native bindings (`src/csharp/Native/`)

Auto-generated P/Invoke wrappers via ClangSharpPInvokeGenerator. **Never edit `Generated/` by hand.** Each plugin gets a corresponding bindings csproj:

- `KernelEngine.Kernel.Native` — wraps `ke_kernel`
- `KernelEngine.Runtime` — wraps `ke_runtime`
- `KernelEngine.Ecs.Flecs` — wraps the flecs ECS plugin
- `KernelEngine.Render.Bgfx.Native`, `KernelEngine.Window.Glfw.Native`, `KernelEngine.Asset.Assimp.Native`, `KernelEngine.TaskScheduler.Enki.Native`

Regenerate with `dotnet run scripts/generate_bindings.cs`. Each project has a `.rsp` file controlling which headers are processed and which types are excluded.

### Layer 4 — C# managed (`src/csharp/`)

Thin wrappers expose the native vtables as managed types. Game code talks to these.

The composition pattern (current target shape) — a runtime module host:

```csharp
var services = new ServiceCollection()
    .AddKernel()
    .AddLogger().AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "Title"))
    .Add<IRuntimeModule>(new BgfxRenderModule(shaderPath: ..., vsync: true));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();
runtime.LoadModules(sp);

while (!window.ShouldClose()) {
    runtime.Tick(dt);
}
```

Game code becomes a runtime module too, registering its own components + systems via `IRuntimeModule.OnLoad(IRuntime)`. See `examples/csharp/01_runtime_clear_color/Program.cs` for the smallest working host.

---

## Threading model

Two named workers exposed by the scheduler:

```
ke.sim    — runtime tick loop; runs every sim system + the window/input poll
ke.render — pinned render-thread work; WebGPU device/queue calls are made here only
```

`ke.main` from the older Application.cs model is folded into `ke.sim`. There is no separate input thread; GLFW poll runs at the top of each tick before the scheduler dispatches.

**Sim ↔ render boundary**: per-component snapshot via double-buffered ECS storage (locked design — `docs/RuntimeArchitectureV2.md` §16). Components touched by render-phase systems get `KE_COMPONENT_DOUBLE_BUFFERED` set automatically (inferred from system access lists). Phase boundaries rotate the snapshot index; sim N+1 writes the live side while render N reads the snapshot side. No lock, no per-frame copy, no frame-packet object — the old `ke_frame_packet` extract path was deleted in C-phase 4 of the runtime arc.

**Pre-R6 transitional state**: snapshot mechanism is not yet wired (R6-R7). Sim and render run serially on the same world; render-phase systems just read live storage. Performance equivalent to the historical "1 thread for everything" model; correctness preserved. R6+ flips on pipelining transparently to render-side code.

**Worker pool**: a single shared `ke_task_scheduler` (enkiTS). The runtime's wave dispatcher submits tasks directly. Every parallel subsystem (asset loading, PSO compile, audio mixing, render dispatch) routes through the same pool. flecs is built without its pipeline addon, so flecs itself never spawns a thread.

---

## Coding conventions

### C / C++
- **Extensions**: `.h`/`.c` for C; `.hpp`/`.cpp` for C++.
- **Naming**: C → `snake_case` with `ke_` prefix everywhere. C++ → `PascalCase` types (Google C++ Style).
- **Namespaces (C++)**: `kernel_engine::<domain>::<subdomain>`. `using namespace` is forbidden in headers.
- **Headers**: `#pragma once` always. Public API in `include/`; private impl headers next to `.cpp` files, never included externally.
- **Formatting**: `BasedOnStyle: Microsoft` (`.clang-format` at root).
- **Error handling**: C layer returns `ke_result`. No exceptions in C. All callers handle the result.
- **Memory**: `ke_allocator` is an **internal implementation utility**, not a public API. C implementations use `ke_allocator_malloc` (or `arena`, `proxy`) internally — PRIVATE to each impl. Factory functions do **not** take `ke_allocator*` as a parameter. In debug builds, impls link `ke_allocator_proxy` PRIVATE and emit a leak report on destroy. Raw pointers are non-owning unless documented otherwise.
- **Param structs**: standardize on `_params` suffix for parameter bags (construction, registration, etc.). Never `_desc`, `_descriptor`, `_info`, or `_config`.
- **No `impl_` / `Impl` / `_impl` naming**: vtable function-pointer slots use `<plugin>_<verb>`; state structs use `XxxState`; filenames are plain. Pattern grew by inertia and is rejected in new code.

### C#
- XML doc comments (`///`) on all `public` and `protected` members.
- Generated bindings in `Generated/` — never edit manually.
- `InternalsVisibleTo` is **banned**. Cross-binding access goes through public `Native` pointers, following the `Allocator.Native` precedent. Existing entries in `KernelEngine.Ecs.Flecs.csproj`, `KernelEngine.Runtime.csproj`, `KernelEngine.Kernel.csproj` are debt being cleaned up; new entries are rejected.

### Git / commits
- Conventional Commits: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.
- One commit per logical task. Stage files selectively — never `git add .`.
- Commit messages are a single line. No multi-line body. No `Co-Authored-By` footer.

---

## Project rules

1. **Plugins implement vtables; contract headers declare them, factory headers create them, period.** No plain exported functions in plugin contract headers. The plugin's symbol surface to the rest of the engine is the factory function and the vtable methods it returns. Kernel built-ins are the only header path allowed to export plain symbols.

2. **No `InternalsVisibleTo`.** See above. Use public `Native` pointers.

3. **Search precedents before inventing.** The project is mature enough that almost every structural decision has an existing example. Before designing a new plugin layout, a new binding `.rsp`, a new plugin `build.zig`, a new vtable split — find the closest existing case in the repo. Match the established pattern; if it's genuinely wrong, propose changing the pattern explicitly rather than diverging in parallel.

4. **Consult legacy before rewriting.** When porting a concept off legacy code into a new framework/runtime, read the legacy implementation first, then design the replacement consciously. Refazer (rewriting from scratch) is sometimes correct; refazer-blind (without consulting what was there) is never correct. Legacy code carries hard-won lessons (edge cases, conventions, lifecycle hooks); skipping it means re-discovering them as regressions.

5. **No mutex / condvar / `std::thread` in plugins.** The scheduler is the synchronization layer. Async completion uses `ke_task_scheduler->submit_to(thread, fn, ctx)` + `wait_for_task`. Producer-consumer ordering uses phase boundaries (register producer in phase N, consumer in phase N+1; the runtime guarantees the barrier). The legacy `ke_resource_queue` that reinvented a Future on `std::mutex` + `condition_variable` was deleted in C-phase 4.5 of the runtime arc.

6. **`assert()` and `abort()` are banned everywhere in engine code.** The engine has `ke_error` — a robust, typed, thread-local error propagation system. Any condition that would be expressed as `assert(x)` must instead be expressed as a `ke_result` return + `KE_ERROR_SET`. Any path that would call `abort()` must translate to `ke_error` and return an error code to the caller. This includes `ke_thread_assert_current` (which uses `assert()` and must be replaced with a `ke_result`-returning check), internal defensive guards, and plugin boundaries. Delegating failure to the OS abort dialog when a proper error system exists is a hard violation.

7. **Framework plugin is implemented in pure C.** `src/c/framework/` ships pure C only — no STL, no `new`/`delete`, no C++ standard library. tomlc99 (vendored) handles TOML parsing. The framework's public-facing surface is C-ABI vtable + factory functions, so C++ name-mangling at the implementation layer would only add friction for dynamic-language bindings (Lua, future Rust).

8. **No magic numbers — we are engine developers, not game developers.** A numeric constant is only allowed to stay a bare `const` when it is truly non-dynamic — implied by the algorithm itself, with no other value that would ever make sense (a 4x4 matrix, a quaternion's 4 components). Every other constant is a **game-tuning or workload-shape value**, and imposing it on the caller as a hardcoded ceiling is not our call to make. It must be a constructor parameter or params-struct field, with the current value kept only as the default for convenience. This applies especially to anything found to be a real limiting factor — a buffer size, a per-bucket cap, a grid resolution — where exceeding it produces a hard failure or visible artifact instead of graceful degradation. Stress tests exist to discover a *sane default*, not to justify a hardcoded ceiling; once a constant is shown to be limiting, promote it to a field rather than tuning the number in place. Don't flood constructors with parameters nobody sets — only promote what's actually been shown to matter.

---

## Key documents

| Doc | What it covers |
|---|---|
| [`docs/RuntimeArchitectureV2.md`](docs/RuntimeArchitectureV2.md) | The runtime contract (scheduler + ECS + module/system lifecycle + phase enum). §15 = script safety model. §16 = sim/render pipelining via component snapshot. §17 = V1 merge arc — **§17.6 is the live execution log + current branch state + next phases**. |
| [`docs/RenderArchitectureV2.md`](docs/RenderArchitectureV2.md) | The future renderer design (`ke_gpu_device` WebGPU-style ABI, Slang shaders, three-mechanism PSO management, render-graph integration). Reconciled with runtime V2 (§9 integration, §11 culling, §12 non-goals). |
| [`docs/EngineRoadmap.md`](docs/EngineRoadmap.md) | Product roadmap (M1–M5). What the engine does at each milestone + recommended external libraries per feature category. Read first to understand strategic direction. |
| [`docs/Kanban.md`](docs/Kanban.md) | Active and pending work. Architectural principles at top; cards with Why/What/Acceptance/Steps. |
| [`docs/Reference/`](docs/Reference/) | Consolidated engine reference (arc42-style chapters). Older snapshot of the architecture; runtime/render details have moved into the V2 docs above as those settled. |
| [`docs/Development/ProjectGuidelines.md`](docs/Development/ProjectGuidelines.md) | Conventions and anti-patterns. Plugin architecture, naming, header discipline, C# layer rules. The reference for code review. |
