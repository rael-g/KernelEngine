# Done Audit Sweep 2026-06-08

## Tier: Core / Architecture
- [x] **[F.RC2] Render-graph + GPU-compute primitives**: `render_graph.h` contract + `RenderGraphImpl` shipped. `create_render_graph` / `get_render_graph` on the `ke_render` vtable.
- [x] **[F.RC3] Clustered Forward Shading**: Tiled light culling implemented in `core/` with `cs_light_cull.sc` compute shader. Support added to `ke_render` vtable.
- [x] **3-Thread Architecture (Deadlock-Free Pillar 1)**: Implemented `ke.main` / `ke.sim` / `ke.render` split with one-directional snapshot exchange, making cross-thread deadlocks much harder to accidentally introduce.

## Tier B — Missing Capabilities
- [x] **B1 Sprite + Sprite2D node**: `Sprite2D.cs` shipped and used for textured quads.
- [x] **B2 Camera2D orthographic helper**: `Camera2D.cs` shipped with proper unit/pixel scale management.
- [x] **B4 CLI scaffold — ke new project / ke run**: `ke new game <name>` implemented in `Commands.NewGame`, produces complete sln/csproj structure.
- [x] **B5 Input action layer**: `InputActions.cs`, `InputActionMap.cs`, and `ke add inputaction` CLI verb all shipped. Native TOML loader implemented.

## Tier P — Ergonomics & Pong Polish
- [x] **P1 UI primitives — text rendering**: `Label.cs`, `Font.cs`, `LabelRenderSystem.cs` shipped; `Text.StbTrueType` plugin provides high-fidelity glyph generation.
- [x] **P2 CLI editor — ke add reference / module**: implemented in `Commands.cs` + `ProgramCsSync.cs` with Roslyn-backed Program.cs synchronization.

## Tier S — Scripting ABI / Framework Promotion (Phase 1)
- [x] **Tier S Stage 1 — Framework ABI**: Promoted SceneTree, NodeTypeRegistry, ResourceCache, and InputActions to C-contract layer (`src/c/kernel/include/kernel_engine/framework/`).
- [x] **Framework Implementation**: Single `ke_framework` shared library (C++/C) implementing all 5 major concepts, replacing the previously C#-only implementations.
- [x] **Native Scene Loading**: Support for `[entity.scene] path = "..."` and recursive loading implemented natively in `scene_loader.cpp`.
- [x] **Layer Split**: Established the parallel `src/c/framework/` structure for pure-logic concepts, keeping `src/c/kernel/` for primitives.

## Tier T — Testing & Instrumentation
- [x] **T0 / T8 — Unified Coverage Pipeline**: Rewritten as `scripts/coverage.py`. Uses Clang source-based instrumentation for Native and Coverlet for Managed code. Generates a unified HTML report with L1/L2/L4 layering. Meta of 80% coverage reached this session.
- [x] **Native Coverage Fix**: Resolved instrumenting issues for native plugins (audio, dev_platform, physics, task_scheduler, text). `dev_platform.win32` jumped 0% → 100%.
- [x] **T4 — Configuration Coverage**: Achieved 98.6% coverage for `KernelEngine.Configuration` via integration tests in `KernelEngine.Kernel.Tests`.
- [x] **T6 — Leftover Folder Cleanup**: Eliminated `src/csharp/KernelEngine.Contracts/` (replaced by `KernelEngine.Kernel.Abstractions`).

## Tier H — Hygiene & Instrumentation
- [x] **H5 [U.1] VSync configuration**: wired `WindowConfig.vsync` through to `bgfx::reset`, allowing uncapped FPS for benchmarking.
- [x] **[Y.10] Bindings-drift script**: `scripts/check_bindings_drift.py` implemented to detect when C headers and C# bindings are out of sync.

## Bug Fixes & Hardening (Problem Catalog)
- [x] **Bug 1.26 — EntryPointNotFound Resolution**: Verified that layer boundary cleanup (W.4) resolved library-level entry point issues.
- [x] **Bug 1.22 — System Context Sanitization**: Finalized removal of direct `ke_render*` access from simulation-side system contexts.
- [x] **Bugs 1.1 - 1.8 Core Hardening**: Successfully implemented API Migration (1.1), Input Snapshots (1.2), Structured Shutdown (1.3), Handle Safety (1.5), Thread Affinity (1.6), and Dead Code/Pipe Removal (1.7, 1.8).
- [x] **Bugs 1.27 - 1.39 Layer Cleanup**: 
    - [x] **[W.4] Layer Boundary Cleanup (Phase 2)** — commit `9a87a37`. Public API leaks closed in `src/cpp/render/`.
    - [x] **[W.6] Move Internal-Only Headers from `include/` to `src/`** — commit `2131aa2`.
    - [x] **[W.7] Move `get_last_fatal_error` from bgfx Plugin to `ke_render` Vtable** — commits `2131aa2`, `a97d9a8`, `9a87a37`.
    - [x] **[W.8] Rename Namespace `kernel_engine::render::bgfx` → `kernel_engine::render::core`** — commit `2131aa2`.
    - [x] **[W.9] Standalone Agnostic render/core**: `bgfx_system_factory.h` deleted; core exports one `_create` entry point.
    - [x] **[W.10] Audit `bgfx_shader_compiler` Plugin**: Cleaned up public headers and file extensions.
    - [x] **[W.11] Fix File Extensions**: `.hh`/`.cc` migrated to `.hpp`/`.cpp`.
    - [x] **[W.12] Rename PascalCase Filenames to snake_case (16 files)**.
    - [x] **[W.13] Remove `using namespace` Violations**.
    - [x] **[W.14] Misc Naming/Structure Cleanups**: standardized `_export.h` and threading consolidation.
    - [x] **[W.15] Eliminate `src/csharp/Native/` Folder — Single Project per Plugin**.
    - [x] **[W.16] Move `ke_console_sink_create` Out of the Kernel**.
