# Done — KernelEngine Achievements Log

Archival list of completed work, extracted from `docs/Kanban.md` so the active board doesn't grow unbounded. New entries append to the bottom; nothing is ever deleted here. The Kanban itself only holds active and roadmap items.

---

## Pre-extraction (legacy entries)

- [x] **[Y.4] Symbolic Result Names**: `KernelException` maps all `ke_result` codes.
- [x] **[W.4] Microkernel Hardening**: Moved TLS/Utilities from C++ plugin to C kernel.
- [x] **[P Wave 1] PAL Foundation**: `IDevPlatform` with Win32/Posix backends.
- [x] **[F] Structured Shutdown**: `join_timeout` + `CancellationTokenSource`.
- [x] **[H] MessagePipe Removal**: Dead code eliminated.
- [x] **[E] API Migration**: Examples 01–05 using `IResourceFactory`/`ISceneWriter`.
- [x] **[Y.1] bgfx Fatal Callback**: Captures file/line on abort.
- [x] **[Y.7-Y.9] Observability**: Log flush, SEH handler, Lifecycle logs.
- [x] **[B] Dead Code removal**: `GlfwWindow.cpp` deleted.
- [x] **[A] Handle Safety**: `UINT32_MAX` sentinel and typed handles.

## Sweep 2026-06-05 — legacy Kanban "BLOCK 5 cleanup" archive

Cleanup cards completed during the multithread-architecture branch consolidation. Full bodies removed from `Kanban.md` to keep it focused on live work.

- [x] **[W.4] Layer Boundary Cleanup (Phase 2)** — commit `9a87a37`. Public API leaks closed in `src/cpp/render/`.
- [x] **[W.6] Move Internal-Only render/core Headers from `include/` to `src/`** — commit `2131aa2`.
- [x] **[W.7] Move `get_last_fatal_error` from bgfx Plugin to `ke_render` Vtable** — commits `2131aa2`, `a97d9a8`, `9a87a37`.
- [x] **[W.8] Rename Namespace `kernel_engine::render::bgfx` → `kernel_engine::render::core`** — commit `2131aa2`.
- [x] **[W.9] Promote `render/core` to Standalone Agnostic Plugin (eliminate "system factory" pattern)** — `bgfx_system_factory.h` deleted; `render/core` exports one `_create` entry point; backend swap = implement `ke_render` vtable + reuse `render/core` unchanged.
- [x] **[W.10] Audit `bgfx_shader_compiler` Plugin (class in public header + wrong extensions)** — commits `e953bcc`, `b41bf88`.
- [x] **[W.11] Fix File Extensions (`.hh` → `.hpp`, `.cc` → `.cpp`)** — commit `e953bcc`.
- [x] **[W.12] Rename PascalCase Filenames to snake_case (16 files)** — commit `a3f9e0d`.
- [x] **[W.13] Remove `using namespace` Violations** — no remaining occurrences in `src/cpp` or `src/c` headers.
- [x] **[W.14] Misc Naming/Structure Cleanups** — `enki_task_scheduler` header rename, plugin threading consolidation, `_export.h` standardized location (commits `2b6f9f4`, `a462d75`, `36551ce`).
- [x] **[W.15] Eliminate `src/csharp/Native/` Folder — Single Project per Plugin** — commit `2131aa2`.
- [x] **[W.16] Move `ke_console_sink_create` Out of the Kernel** — commit `ecbad90` (Option B).

## Sweep 2026-06-08 — user-curated Kanban audit (folded from `done-2.md`)

> ⚠️ **Re-audit required (Kanban Z1, 2026-06-11)**: this sweep folded items without running the examples / tests that prove they work end-to-end. Confirmed errors so far: OBS.4 example 10 bloom listed as broken in memory but reportedly runs (user 2026-06-11); SSAO confirmed still broken. Do not trust the entries below until Z1 re-verifies each one against a working example/test.

Capabilities the user shipped during the 4-day pause; verified against the current tree before removing from Kanban.

### Render-pipeline foundation
- [x] **[F.RC2] Render-graph + GPU-compute primitives** — `src/c/kernel/include/kernel_engine/kernel/render/render_graph.h` (242 lines) public contract + `src/cpp/render/core/src/render_graph_impl.hpp` (137 lines) impl; `create_render_graph` / `get_render_graph` slots on the `ke_render` vtable. Replaces the hardcoded view chain for SSAO/bloom/tonemap.
- [x] **[F.RC3] Clustered forward shading** — `cs_light_cull.sc` compute shader shipped under `src/cpp/render/bgfx/shaders/compiled/{dx11,essl,glsl}/`; tile-based light culling promoted to `ke_render` vtable. Removes the ~64 point / 48 spot brute-force cap.
- [x] **`[DEADLOCK-FREE]` Pillar 1 — 3-thread architecture (ke.main / ke.sim / ke.render)** — one-directional snapshot exchange shipped; cross-thread data writes only via FrameSync/queue handoffs. Pillars 2 (phantom thread tokens) + 3 (API-by-absence) + analyzer still pending — card stays open for the remaining work.

### Tier B — non-physics/UI features
- [x] **B1 — Sprite + `Sprite2D` node** — `src/csharp/KernelEngine.Framework/Nodes/Sprite2D.cs` shipped for textured-quad rendering.
- [x] **B2 — `Camera2D` orthographic helper** — `src/csharp/KernelEngine.Framework/Nodes/Camera2D.cs` shipped with pixel/unit scale.
- [x] **B4 — CLI scaffold (`ke new project` / `ke run`)** — `src/csharp/KernelEngine.Cli/Commands.cs` ships `NewGame` producing sln+csproj+Program.cs+Project skeleton. v1 (curated `dotnet new` template pack) tracked as P14.
- [x] **B5 — Input action layer** — `InputActions.cs`, `InputActionMap.cs`, `ke add inputaction` verb, native TOML loader. Closes OBS.5 §3 edge-poll dependency.

### Tier P — Pong continuation
- [x] **P1 — UI primitives (text + Label)** — `src/csharp/KernelEngine.Framework/Text/{Label,Font}.cs` + `LabelRenderSystem.cs` shipped; `KernelEngine.Text.StbTrueType` plugin provides glyph baking via stb_truetype.
- [x] **P2 — CLI editor (`ke add reference` / `ke register`)** — `Commands.cs` + `ProgramCsSync.cs` ship Roslyn-backed Program.cs synchronization; `ke add reference KernelEngine.X` updates csproj AND Program.cs together.
- [x] **P14 MVP — `ke new game <Name>` wraps `dotnet new`** — chains stock `dotnet new sln`/`console` + Program.cs patch; v1 template-pack (`ke.templates.game`) deferred (still in Kanban as `P14 | v1 only`).

### Tier S — Framework ABI promotion (Stage 1)
- [x] **Framework ABI promoted to C contract layer** — `src/c/kernel/include/kernel_engine/framework/` headers: `scene_tree.h`, `scene_loader.h`, `resource_cache.h`, `input_actions.h`, `mesh_render_system.h`, `light_render_system.h`, `camera_render_system.h`, `material_file.h`, `mesh_shape.h`, `mesh_asset_system.h`, `asset_resolver.h`, `framework_export.h`. Promotes SceneTree / NodeTypeRegistry / ResourceCache / InputActions to language-agnostic surface.
- [x] **`ke_framework` single shared-library plugin** — `src/cpp/framework/` consolidates the framework concept impls (replaces the C#-only versions). Pure-logic concepts live under the parallel `src/c/framework/` structure.
- [x] **Native scene-loading with `[entity.scene]` references** — recursive scene composition implemented in `src/cpp/framework/src/scene_loader.cpp`; bindings (C# / Lua) drive it identically.

### Tier T — Testing & coverage
- [x] **T4 — `KernelEngine.Configuration` coverage** — TOML binder + ServiceCollectionExtensions now covered via `KernelEngine.Kernel.Tests` (98.6% reported by `scripts/coverage.py`).
- [x] **T6 — `KernelEngine.Contracts/` leftover folder** — deleted; superseded by `KernelEngine.Kernel.Abstractions`.

### Tier H — Hygiene & instrumentation carry-overs
- [x] **H1 / [Y.10] — Bindings-drift detection script** — `scripts/check_bindings_drift.py` shipped; detects when C headers and generated C# P/Invoke bindings fall out of sync (Bug 1.25 mitigation).
- [x] **H5 / [U.1] — VSync configuration** — `WindowConfig.vsync` wired through to `bgfx::reset` for uncapped-FPS benchmarking.

### Bug catalog mop-up
- [x] **Bug 1.22 — Renderer pointer in system context** — finalized removal of direct `ke_render*` from sim-side system contexts.
- [x] **Bug 1.26 — `EntryPointNotFoundException`** — confirmed resolved by W.4 layer-boundary cleanup; no further symptom on the multithread branch merge.
- [x] **Bugs 1.1–1.8 core hardening** — API migration (1.1), input snapshots (1.2), structured shutdown (1.3), handle safety (1.5), thread affinity (1.6), dead-code paths (1.7), dead `ke_message_pipe` (1.8) — all shipped during the multithread-branch consolidation.

## Sweep 2026-06-09 — session housekeeping (test + commit pass)
- [x] **Test-enabler reverts** — `KernelThread.AssertCurrent` restored `#if DEBUG` guard (was unconditionally throwing); `enki_task_scheduler::is_completed` restored `if (!task) return true` semantic. Affected integration test updated to assert the documented behavior. Source was not the right thing to mutate to satisfy a test.
- [x] **Integration-tests working directory** — `gtest_discover_tests` for `test_integration_cpp` now runs from `${CMAKE_SOURCE_DIR}`, so `assets/Box.gltf` etc. resolve without per-test copies. 2 previously-skipped `AssetLoaderTest` cases now execute. T10 tracks the longer-term fixture refactor.
