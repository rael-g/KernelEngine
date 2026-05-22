# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build commands

### C/C++ (CMake + vcpkg + Ninja + Clang)

```bash
# Configure
cmake --preset win      # Windows
cmake --preset linux    # Linux

# Build
cmake --build --preset win

# Install (required for C# to find native DLLs)
cmake --install build/win --prefix build/native

# Run C/C++ tests
ctest --preset win --output-on-failure

# Run a C example
./build/win/bin/01_minimal_log.exe
```

Build output: `build/win/bin/` (executables + DLLs), `build/win/lib/`. C# expects native libraries at `build/native/bin/` (Windows).

### C# (.NET 10)

```bash
dotnet build
dotnet test KernelEngine.slnx
```

### Scripts

```bash
python scripts/compile_shaders.py   # compile all bgfx shaders to SPIR-V
python scripts/generate_bindings.py # regenerate all C# P/Invoke bindings via ClangSharp
python scripts/run_tests.py         # C/C++ + C# tests with coverage report (gcovr + reportgenerator)
```

Shaders compile to `src/cpp/render/bgfx/shaders/compiled/spirv/`. Bindings run `dotnet tool restore` from `src/csharp/` first, then process every `.rsp` file under `src/csharp/Native/`.

### Running examples after a native rebuild — never use `dotnet run --no-build`

Native DLLs (`ke_*.dll`) are copied into each example's output via a `PreserveNewest` item in `NativeDependencies.targets`, but that copy only runs during a build. So after a `cmake --build` (new native code), `dotnet run --no-build` keeps the **stale** DLL already in `bin/Debug/net10.0/` and you silently run old C++ (Bug 1.42). Always run `dotnet run` / `dotnet build` (no `--no-build`) — the timestamp-based copy then refreshes the native DLL automatically.

---

## Architecture

KernelEngine is a microkernel game engine with four strict layers:

### Layer 1 — C Kernel (`src/c/kernel/`)

Pure C, ABI-stable (`extern "C"`). All structs use vtable-style function pointers. Public headers under `include/kernel_engine/kernel/`, private impl under `src/`.

Key types:
- `ke_allocator` — explicit allocator, passed to every major component
- `ke_logger` / `ke_logger_sink` — pluggable logging
- `ke_world` — owns the ECS registry and system graph
- `ke_ecs_registry` — sparse-set ECS; `ke_entity` is `uint64_t`
- `ke_frame_packet` — per-frame snapshot written by ke.sim, read by ke.render
- `ke_render` / `ke_window` — vtable interfaces for renderer and window backends
- `ke_input_snapshot` — immutable input state passed across thread boundary

CMake target: `ke_kernel` (alias `ke::kernel`).

### Layer 2 — C++ plugins (`src/cpp/`)

Each plugin is a shared library exposing a single C factory function:
- `src/cpp/render/bgfx/` → `render_bgfx_create()` — bgfx renderer
- `src/cpp/window/glfw/` → `ke_window_glfw_create()` — GLFW window
- `src/cpp/render/bgfx_shader_compiler/` — shader compiler wrapper
- `src/cpp/dev_platform/` — optional dev-only OS facilities (thread naming, future: crash handler, minidump)
- `src/cpp/asset/assimp/` — Assimp mesh/texture loader
- `src/cpp/threading/` — `KeFrameSync`, `KeSemaphore`, `KernelThread` (C++ impl of C threading API)
- `src/cpp/task_scheduler/enki/` — enkiTS parallel task scheduler

The bgfx plugin is internally split into sub-libraries (`render/core/`, `render/bgfx_device/`). `FrameSubmitter` consumes a `ke_frame_packet` and issues all draw calls.

#### **Layer boundary rule (non-negotiable)**

- **`src/c/kernel/include/`** is the **sole** source of public engine API. Every interface, vtable, struct, enum, and function the engine exposes to consumers lives here. C ABI only.
- Each `src/cpp/<plugin>/` exposes **one and only one** thing publicly: a C-ABI creation entry point (`ke_<plugin>_create()`) declared in a single small public header.
- **All other headers under `src/cpp/<plugin>/`** (whether under `include/` or `src/`) are **implementation detail** — `.hpp` files with C++ classes, internal helpers, private state. **Consumers must never include them.**
- If you find yourself wanting to expose a generic utility (thread naming, logging helper, math), it belongs in `src/c/kernel/`, not in a plugin's public header. Implement it in C (use C11 `_Thread_local` etc., not C++).
- When auditing: any `.h` (not `.hpp`) under `src/cpp/<plugin>/include/` containing more than the create function is a violation. Surface it to the user before propagating the broken pattern.

### Layer 3 — C# native bindings (`src/csharp/Native/`)

Auto-generated P/Invoke wrappers via ClangSharpPInvokeGenerator. **Never edit `Generated/` by hand.** Each plugin has a corresponding native project:
- `KernelEngine.Kernel.Native` — wraps `ke_kernel`
- `KernelEngine.Render.Bgfx.Native` — wraps bgfx render plugin
- `KernelEngine.Window.Glfw.Native` — wraps GLFW window plugin
- `KernelEngine.Asset.Assimp.Native` — wraps Assimp plugin
- `KernelEngine.TaskScheduler.Enki.Native` / `KernelEngine.Threading.Native`

Regenerate with `python scripts/generate_bindings.py`. Each project has a `.rsp` file controlling which headers are processed and which types are excluded.

### Layer 4 — C# managed layer (`src/csharp/`)

**`KernelEngine.Kernel/`** — thin wrappers over native types. Key classes:
- `Allocator` (abstract) → `MallocAllocator`, `ArenaAllocator`
- `Logger`, `ILoggerSink`, `ConsoleSink`
- `Window`, `Renderer`, `Input`
- `World` — wraps `ke_world`; exposes `Scene`, `AddSystem(ISystem)`, `ActiveCamera`
- `Scene` — `AddNode(string, parent?)`, `AddNode<T>(T, string, parent?)`
- `Node` — ECS-backed, subclassable; `OnStart()`/`OnUpdate(float)` virtuals
- `EcsRegistry`, `EcsQuery<T>` — component query (ref struct)
- `FrameSync` — double-buffer ring between ke.sim (writer) and ke.render (reader)
- `KernelThread` — named thread creation + `AssertCurrent(name)` for thread-affinity debug checks
- `ISceneWriter` / `FramePacketSceneWriter` — frame-level commands safe to call from ke.sim
- `IResourceFactory` / `ResourceCommandFactory` — GPU resource creation routed through `ResourceCommandQueue` to ke.render
- `IInputReader` / `InputBuffer` — lock-free input snapshot exchange between ke.main and ke.sim
- Typed handles: `MeshHandle`, `TextureHandle`, `MaterialHandle`, `ShadowMapHandle` — all use `uint.MaxValue` as the None sentinel; `0` is always a valid handle (built-in white texture)

**`KernelEngine.Framework/`** — high-level Framework. Key classes:
- `Application` — orchestrates 3 threads (see threading model below)
- Nodes: `MeshNode`, `CameraNode`, `LightNode`, `PointLightNode`, `SpotLightNode`, `SkyboxNode`
- Systems: `MeshRenderSystem`, `CameraRenderSystem`, `LightRenderSystem`, `ShadowRenderSystem`, `SkyboxRenderSystem`

**Plugin wrapper projects** (thin service registration only):
- `KernelEngine.Render.Bgfx/` → `AddBgfxRenderer(shaderPath)`
- `KernelEngine.Window.Glfw/` → `AddGlfwWindow(width, height, title)`
- `KernelEngine.Asset.Assimp/` → asset loading helpers
- `KernelEngine.Logging.Serilog/` → Serilog sink

---

## Threading model

`Application.Run()` owns three named threads:

```
ke.main   — GLFW PollEvents, Input.Update, InputBuffer.Produce
ke.render — Renderer.Initialize, ResourceCommandQueue.Drain, SubmitPacket, Frame
ke.sim    — World.Update, OnUpdate, FrameSync producer
```

`FrameSync` is a 2-slot ring buffer. ke.sim calls `BeginWrite`/`EndWrite`; ke.render calls `BeginRead`/`EndRead`. Both block on semaphores when no slot is available.

`InputBuffer` is a lock-free single-slot exchange: ke.main produces, ke.sim consumes at the start of each `World.Update`.

`ResourceCommandQueue` is a `ConcurrentQueue` drained by ke.render at the top of each frame, before reading the frame packet. `ResourceCommandFactory` enqueues commands and blocks ke.sim via `TaskCompletionSource<uint>` until ke.render returns the handle.

Thread-affinity violations are caught at runtime in debug builds via `ke_thread_assert_current` (C/C++) and `KernelThread.AssertCurrent` (C#).

---

## Game developer entry point

```csharp
var services = new ServiceCollection()
    .AddKernel()
    .AddLogger().AddConsoleSink()
    .AddInput()
    .AddGlfwWindow(1280, 720, "Title")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = (IResourceFactory resources) => {
    // called once on ke.sim after ke.render is initialized
    var mesh = resources.CreateMesh(verts, indices);
};

app.OnUpdate = (ISceneWriter scene, IInputReader input) => {
    // called every sim frame
    scene.ClearColor(0.1f, 0.1f, 0.1f, 1f);
    if (input.IsKeyDown(87)) { /* W */ }
};

app.Run(services);
```

**Do not call `app.Renderer` from `OnReady` or `OnUpdate`** — those run on ke.sim; bgfx APIs are ke.render-only.

---

## Coding conventions

### C / C++
- **File extensions**: `.hpp`/`.cpp` for C++, `.h`/`.c` for C.
- **Naming**: C++ — `PascalCase` types (Google C++ Style); C — `snake_case` with `ke_` prefix everywhere.
- **Namespaces**: `kernel_engine::domain::subdomain`. Standard: `kernel_engine::render` for HAL contracts, `kernel_engine::render::core` for agnostic core, `kernel_engine::render::bgfx` for bgfx implementation. `using namespace` is forbidden in headers.
- **Headers**: `#pragma once` always. Public API in `include/`; private impl headers next to `.cpp` files, never included externally.
- **Formatting**: `BasedOnStyle: Microsoft` (`.clang-format` at root).
- **Error handling**: return `ke_result`; no exceptions in the C layer. All callers must handle it.
- **Memory**: every major component receives an explicit `ke_allocator*`. Raw pointers are non-owning unless documented.
- **Naming (Structs)**: Standardize on `_params` suffix for structs that aggregate construction or registration parameters (parameter bags). NEVER use `_desc`, `_descriptor`, `_info`, or `_config`.

### C#
- XML doc comments (`///`) on all `public` and `protected` members.
- Generated bindings in `Generated/` — never edit manually.

### Git / commits
- Conventional Commits: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.
- 1 commit = 1 logical task. Never `git add .`; stage files selectively.
- Commit message must be a single line. No multi-line body, no `Co-Authored-By`.

---

## Key docs

- `docs/Reference/` — **consolidated engine reference** (12 chapters, arc42-style): what the engine is + will be, by domain (philosophy, layers, kernel, plugins, C# layers, framework, graphics, multithreading, assets, build, roadmap). Start at `docs/Reference/00 - Overview.md`. Supersedes the former `docs/Architecture/` vision docs.
- `docs/EngineRoadmap.md` — **product roadmap (M1–M5)**. What the engine does at each milestone + recommended external libraries per feature category. Read first to understand the strategic direction.
- `docs/Kanban.md` — **active and pending work**. Architectural principles at top; cards with Why/What/Acceptance/Steps; bug-to-card mapping at bottom.
- `docs/Reference/12 - Architecture Backlog & Decisions.md` — **design rationale + bug catalog**. Detailed defect descriptions, target architecture, decisions log. NOT a status board.
- `docs/Development/ProjectGuidelines.md` — **conventions and anti-patterns**. Plugin architecture, naming, header discipline, C# layer rules. The reference for code review.
