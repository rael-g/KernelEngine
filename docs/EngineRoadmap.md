# Engine Roadmap

Strategic milestones for KernelEngine **as a product**. Defines what the engine *is* at each stage and the path to get there.

> **What this is**: product-level milestones (M1 → M5+) and feature categories per milestone.
> **What this is NOT**: bug catalog (see `Architecture/08 - Engine Architecture Backlog.md` § 1) or task tracking (see `Kanban.md`).

---

## ⚠️ Master architectural principle

> **The engine owns the contract. External libraries do the heavy lifting.**

Every feature category is split into two layers:

1. **Universal API in the kernel** — a vtable defined in `src/c/kernel/include/`, owned by the engine. Stable, backend-agnostic.
2. **One or more backend plugins** — wrappers around battle-tested external libraries (bgfx, Box2D, Jolt, FMOD, Ozz, ENet, etc.). Engineering effort goes into integration and API design, NOT reinventing wheels.

Concrete consequence: when planning a new feature category (audio, physics, animation, networking, UI), the questions are:
1. What's the minimal universal contract for this domain? → that becomes the kernel vtable.
2. Which mature external libraries can implement it? → those become the initial backend plugins.
3. Can we cover at least one shipping target with each library? (mobile, web, console concerns)

**Never** invest in a hand-rolled implementation when a battle-tested external library exists. Exceptions only when:
- No external library covers the use case adequately.
- All external options have license incompatibility.
- The domain is so trivial (e.g., `ConsoleSink` log writer) that a wrapper is heavier than reimplementation.

This principle is what bgfx already exemplifies for rendering — generalize it to every domain.

---

## Milestones

### M1 — Render anything, fast (current focus)

The engine can stand up a window, run the 3-thread model, and render a complex scene at 60 FPS with all the modern lighting tricks. Foundation must be solid before adding gameplay layers.

**Status**: ~80% (foundation + render features done; observability + verification pending)

| Capability | Kernel vtable | Backend(s) | Status |
|---|---|---|---|
| Threading model (3-thread) | `ke_thread`, `ke_frame_sync`, `ke_semaphore` | `KernelEngine.Threading` (std::thread) | ✅ Done |
| ECS | `ke_world`, `ke_ecs_registry` | (built into kernel) | ✅ Done |
| Window | `ke_window` | `KernelEngine.Window.Glfw` | ✅ Done |
| Renderer | `ke_render` | `KernelEngine.Render.Bgfx` (bgfx → Vulkan/D3D/Metal/GL) | ✅ Done |
| Asset loader | `ke_asset_loader` | `KernelEngine.Asset.Assimp` | ✅ Done |
| Shader compiler | `ke_shader_compiler` | `KernelEngine.Render.Bgfx.ShaderCompiler` (shaderc) | ✅ Done |
| Task scheduler | `ke_task_scheduler` | `KernelEngine.TaskScheduler.Enki` (enkiTS) | ✅ Done |
| Logger | `ke_logger`, `ke_logger_sink` | `KernelEngine.Logging.Serilog` (+ console) | ✅ Done |
| Allocator | `ke_allocator` | malloc, arena (kernel built-ins) | ✅ Done |
| Dev platform | `ke_dev_platform` | `KernelEngine.DevPlatform.Win32` | ✅ Done (Win32 only) |
| **Verification (E2E examples)** | — | examples 06–13 | 🔲 In progress (Track Z) |
| **Profiling visibility** | TBD | candidate: Tracy | 🔲 Planned (Phase N) |
| **Bindings drift CI** | — | custom script | ✅ Done (Y.10) |

**Exit criteria for M1**: examples 01–13 all run and demonstrate the rendering features at acceptable framerate; a Tracy/Chrome trace is visible for any frame.

---

### M2 — Framework usable like Godot

The framework feels like Godot to game developers: scenes are files, nodes compose freely, signals connect things, and there's a hot-reload story. Performance and architecture are settled enough that gameplay devs don't fight the engine.

**Status**: ~30% (Scene + Node + lifecycle done; composition and signals missing)

| Capability | Kernel vtable | Backend(s) | Status |
|---|---|---|---|
| Scene + Node + lifecycle (`OnStart`/`OnUpdate`) | (in kernel via ECS) | (in `KernelEngine.Framework`) | ✅ Done |
| Built-in nodes (Mesh, Light, Camera, Skybox) | (no vtable; framework types) | `KernelEngine.Framework` | ✅ Done |
| `.kscene` file format | TBD | likely JSON via System.Text.Json | 🔲 Planned (Kanban W.2) |
| `SceneNode` prefab composition | TBD | (recursive instantiation) | 🔲 Planned |
| **Signals** (Godot-style node events) | TBD | candidate: native C# events or custom dispatcher | 🔲 Not tracked |
| **Groups** (named node collections) | TBD | (in framework) | 🔲 Not tracked |
| **Autoload** (singleton nodes) | TBD | (in framework) | 🔲 Not tracked |
| **Hot reload** of `.kscene` files | `ke_dev_platform.watch_file` | `KernelEngine.DevPlatform.Win32` (extend) | 🔲 Not tracked |
| Resource cache / dedup | `ke_asset_registry` | (in kernel) | 🔲 Planned (Phase Q) |

**Exit criteria for M2**: a non-engine developer can author a small scene as `.tscn`-style file, compose 3 prefabs, connect signals between them, and play in <30s of edit-build-run loop.

---

### M3 — Can ship a real (small) game

The engine has every category a real game needs. It might not be best-in-class in any one, but you can build and ship a small commercial title without being blocked.

**Status**: ~10% (rendering and framework only; gameplay categories absent)

| Capability | Kernel vtable | Recommended backend(s) | Status |
|---|---|---|---|
| **Physics 3D** | `ke_physics` (TBD) | [Jolt](https://github.com/jrouwe/JoltPhysics) (modern, MIT, used by Horizon Zero Dawn) | 🔲 Not tracked |
| **Physics 2D** | `ke_physics_2d` or unified | [Box2D](https://github.com/erincatto/box2d) (mature, MIT) | 🔲 Not tracked |
| **Audio** | `ke_audio` | [miniaudio](https://github.com/mackron/miniaudio) (single-header, public domain) or [FMOD](https://www.fmod.com/) (free for indie, pro features) | 🔲 Not tracked |
| **Animation system** | `ke_animation` | [ozz-animation](https://github.com/guillaumeblanc/ozz-animation) (skeletal, blend trees, MIT) | 🔲 Not tracked |
| **UI system** | `ke_ui` | [Dear ImGui](https://github.com/ocornut/imgui) (immediate, dev/debug) + [RmlUi](https://github.com/mikke89/RmlUi) (retained, HTML/CSS-like, MIT) | 🔲 Not tracked |
| **Input action mapping** | extension of `ke_input` | (in kernel) | 🔲 Not tracked |
| **Save/load** | `ke_save` (TBD) | (in framework, with serialization) | 🔲 Not tracked |
| **Particle system** | `ke_particles` (TBD) | likely custom (GPU compute via bgfx) — research needed | 🔲 Not tracked |
| **Tween / `AnimationPlayer`** | (framework only) | (in framework) | 🔲 Not tracked |

**Exit criteria for M3**: example 14 (or similar) is a small playable scene with physics, audio, character animation, a UI menu, and save/load. Distributed as a runnable EXE.

---

### M4 — Visual editor

The engine has a separate editor application that consumes the engine. Game developers edit scenes, properties, and assets visually.

**Status**: 0% (entirely future)

| Capability | Notes |
|---|---|
| Editor app | Likely a separate solution (`KernelEngine.Editor/`) consuming engine as a library. Tech: Avalonia or WinUI? Or browser-based? Decision pending. |
| Scene inspector | Tree view of scene graph, property editor for selected node |
| Asset browser | Browse/import/preview assets |
| Live preview | Run game inside editor with pause/resume |
| Custom property editors | Plugin system for tooling extensions |

**Exit criteria for M4**: edit-without-coding loop works for 80% of common operations.

---

### M5 — Networking & advanced rendering

| Capability | Kernel vtable | Recommended backend(s) | Notes |
|---|---|---|---|
| **Networking transport** | `ke_network` | [GameNetworkingSockets](https://github.com/ValveSoftware/GameNetworkingSockets) (Valve, BSD) or [ENet](http://enet.bespin.org/) (lightweight) | UDP-based reliable transport |
| **Replication framework** | (in framework) | custom | Build on top of `ke_network` |
| **GPU-driven rendering** | extends `ke_render` | bgfx supports compute; viable | Indirect draw, GPU culling |
| **Real-time GI** | extends `ke_render` | research: DDGI, lumen-likes | Long-term R&D |
| **Ray tracing** | new `ke_render_rt` vtable? | bgfx doesn't expose RT — would need DX12/Vulkan direct backends | Architectural decision needed |

**Exit criteria for M5**: small multiplayer demo (2-4 players, lockstep or rollback).

---

## How to extend this roadmap

When proposing a new feature category:

1. Identify if it's a kernel-level capability (universal contract) or framework-level (depends on user code).
2. If kernel-level: define the vtable shape in `src/c/kernel/include/`. Identify ≥1 external library that can implement it.
3. Pick the milestone (M1–M5) that matches the gap it fills. Add a row to the appropriate table.
4. If the feature requires significant architectural decisions (e.g., "physics on a separate thread?"), open an entry in `Architecture/08 - Engine Architecture Backlog.md` § 5 (Risks & Open Questions).
5. When work begins on the feature, create Kanban cards.

---

## What this roadmap is NOT for

- Bug fixes → `Kanban.md` + `Architecture/08 - Engine Architecture Backlog.md` § 1
- Architectural refactors → `Kanban.md` (Track W cards)
- Code conventions → `Development/ProjectGuidelines.md`
- Per-task status → `Kanban.md`
- Architectural rationale → `Architecture/08 - Engine Architecture Backlog.md` §§ 2, 4, 5, 6

This document answers: *"What can the engine DO at each milestone, and what library powers each capability?"*
