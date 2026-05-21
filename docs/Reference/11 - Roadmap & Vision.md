# Roadmap & Vision

This chapter is the *narrative* of where the engine is going. The authoritative tables live in [`../EngineRoadmap.md`](../EngineRoadmap.md); live task status lives in [`../Kanban.md`](../Kanban.md). This page connects them to the architecture.

## Master principle for all future work

> **The engine owns the contract; external libraries do the heavy lifting.**

Every new feature domain is split into (1) a universal kernel vtable owned by the engine and (2) one or more backend plugins wrapping a battle-tested external library. When planning a domain, ask: *what is the minimal universal contract?* (→ kernel vtable) and *which mature library implements it?* (→ plugin). Never hand-roll what a proven library already does. This is exactly how bgfx serves rendering today — generalized to every domain.

## Milestones

### M1 — Render anything, fast 🚧 (~80%, current focus)
Window + 3-thread model + a complex scene at 60 FPS with modern lighting. Foundation before gameplay.
- ✅ Threading model, ECS, window, renderer, asset loader, shader compiler, task scheduler, logger, allocator, dev platform (Win32).
- 🚧 E2E example verification (examples 06–13), profiler visibility (Tracy), then merge the long-lived branch.
- **Exit**: examples 01–13 all run at acceptable framerate; a frame trace is visible.

### M2 — Framework usable like Godot 🚧 (~30%)
The framework feels like Godot/Unity to game devs: composable nodes, scenes, signals, hot-reload.
- ✅ Scene + Node + lifecycle; built-in nodes.
- 📋 The **Framework High-Level API** initiative (Kanban Tier 2) is the bulk of M2: high-level `Material`/`Mesh`/`Texture`/`Assets`, `Scene.Environment`/`PostProcessing`, input enums + action mapping, `scene.MainCamera`, Scene-as-reuse-unit + `SceneAsset`, `SceneManager`, tags, node events, richer lifecycle, `Time`, camera controllers. See [06 - Framework](06%20-%20Framework.md).
- **Exit**: a non-engine dev authors a small scene, composes a few sub-scenes, connects events, and plays in a fast edit-build-run loop.

### M3 — Can ship a real (small) game 📋 (~10%)
Every category a real game needs, each as a kernel vtable + library-backed plugin:
- **Physics 3D** → Jolt; **Physics 2D** → Box2D; **Audio** → miniaudio/FMOD; **Animation** → ozz; **UI** → Dear ImGui (dev) + RmlUi (retained); **Input action mapping**, **save/load**, **particles**, **tween/AnimationPlayer**.
- **Exit**: a small playable scene with physics, audio, animation, UI, save/load, shipped as an EXE.

### M4 — Visual editor 📋 (0%)
A separate editor app consuming the engine as a library: scene inspector, asset browser, live preview, custom property editors. Tech choice (Avalonia / WinUI / browser) pending.

### M5 — Networking & advanced rendering 📋
Networking transport (GameNetworkingSockets / ENet) + replication; GPU-driven rendering (indirect draw, GPU culling); real-time GI; possibly ray tracing (would need a non-bgfx backend).

## Cross-cutting architectural intents

- **Framework High-Level API** (M2): close every leak where game code touches building blocks (raw handles, `ISceneWriter`, magic keycodes, entity IDs). The node→ECS view model (F.0) is the foundation. See [06 - Framework](06%20-%20Framework.md).
- **Asset pipeline** (`KernelEngine.AssetPipeline`): dispatcher + cache + baking + more loaders (KTX2, baked). See [09 - Assets & Pipelines](09%20-%20Assets%20%26%20Pipelines.md).
- **GPU instancing primitive + `MultiMeshRenderer`**: the canonical example of "a missing *capability* is fixed by extending a contract, not by user-land code." Unblocks grass/crowds/particles. See [07 - Graphics & Rendering](07%20-%20Graphics%20%26%20Rendering.md).
- **Observability**: Tracy profiler for the 3-thread timeline (M1 tail). See [08 - Multithreading](08%20-%20Multithreading.md).
- **New domains as plugins**: physics/audio/animation/UI/networking each get a Framework façade — never raw plugin access from game code (the same rule the asset loader now follows).

## How to extend the roadmap

When proposing a new capability:
1. Is it a kernel-level *capability* (universal contract) or framework-level (depends on user code)?
2. Kernel-level → define the vtable in `src/c/kernel/include/`; identify ≥1 external library to implement it.
3. Pick the milestone it fills; add a row in `EngineRoadmap.md`.
4. If it needs significant architectural decisions, record them in [12 - Architecture Backlog & Decisions](12%20-%20Architecture%20Backlog%20%26%20Decisions.md).
5. When work begins, create Kanban cards.
