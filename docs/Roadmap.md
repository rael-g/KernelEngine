# KernelEngine — Roadmap

Public-facing snapshot of where the engine is going. Each milestone groups capabilities by domain; checked items have shipped. Detail and ordering of active work live in [`Kanban.md`](Kanban.md) (internal). This file answers the visitor's question: *"is feature X planned?"*

Status legend: ✅ shipped — 🚧 in progress — 📋 planned — ❓ under research

---

## M1 — Pre-1.0 foundations *(current)*

Core engine + rendering + Pong-class games shippable.

| Domain | Capability | Status |
|---|---|---|
| **Kernel** | Microkernel C ABI (`ke_world`, `ke_render`, `ke_window`, `ke_input`, allocators, logger, ECS) | ✅ |
| **Rendering** | bgfx-backed renderer (Vulkan/D3D11), PBR + IBL + directional shadows | ✅ |
| **Rendering** | Bloom / SSAO / tonemap chain | 🚧 partial (bloom + SSAO broken; tonemap shipped) |
| **Rendering** | Point/spot shadows | 📋 deferred — see Kanban OBS.6 |
| **Multithreading** | `ke.main` / `ke.sim` / `ke.render` pipeline + enkiTS workers | ✅ |
| **Multithreading** | Concurrency-by-construction (deadlock-free types) | 📋 — see Kanban `[DEADLOCK-FREE]` |
| **Scene** | ECS-pure nodes + component-driven scene loader (`[[entity]]`) | ✅ |
| **Physics** | 2D physics (Box2D plugin) | ✅ |
| **Audio** | Audio playback (miniaudio plugin) | ✅ |
| **Assets** | In-process model/texture loaders (Assimp, stb_image) | ✅ |
| **Assets** | Asset pipeline with cache + manifest + shipping path | 📋 — see Kanban A1 |
| **Scripting** | C# scripting via Node subclasses | ✅ |
| **Scripting** | Lua scripting (spike validated; bindings shipped) | ✅ |
| **Input** | Action mapping layer (`Action.Jump` instead of `Key.Space`) | 📋 — see Kanban B5 |
| **Examples** | Pong (C# + Lua) | ✅ |
| **Tooling** | RenderDoc-integrated workflow | 📋 — required before render refactors |

## M2 — Framework ergonomics & first non-Pong examples

Make the engine feel Godot-like for game developers; ship a platformer-class example.

| Domain | Capability | Status |
|---|---|---|
| Framework | High-level `Material` / `Mesh` / `Texture` / `Assets` | 🚧 |
| Framework | `Scene.Environment` / `Scene.PostProcessing` | 📋 |
| Framework | Reusable camera controllers + 2D camera helper | 📋 |
| Framework | Typed component access without IDs | 📋 |
| Framework | Node query / find / tags / paths | 📋 |
| Framework | Node events (signals → C# events) | 📋 |
| Editor | CLI — `ke new project` / `ke add reference` / `ke register inputaction` | 📋 |
| Editor | Auto-generated `Program.cs` from project manifest | 📋 |
| UI | Text rendering + minimal layout (ImGui-first dev tooling) | 📋 |
| Tooling | Headless mode + screenshot dump (CI visual regression) | 📋 |
| Tooling | Tracy profiler integration | 📋 |
| Examples | Platformer mini | 📋 |
| Examples | "Write a custom render backend" tutorial | 📋 |

## M3 — Gameplay categories

The capabilities most games need: 3D physics, animation, retained-mode UI.

| Domain | Backend / approach | Status |
|---|---|---|
| 3D Physics | Jolt Physics plugin | 📋 |
| Skeletal animation | ozz-animation plugin | 📋 |
| Retained-mode UI | RmlUi plugin (HTML/CSS-like) | 📋 |
| Save / load | Versioned world serialization | 📋 |
| Particles | GPU-compute (research) | ❓ |
| Tween / AnimationPlayer | Pure C# framework | 📋 |

## M4 — Visual editor

| Capability | Notes |
|---|---|
| Editor shell | Tech decision pending (Avalonia / WinUI / browser) |
| Scene inspector + property editor | Built on Editor Lib API |
| Asset browser | |
| Live preview (run game inside editor) | |

## M5 — Networking & advanced rendering

| Capability | Backend / notes |
|---|---|
| Networking transport | GameNetworkingSockets (Valve, BSD) or ENet |
| Replication framework | On top of transport |
| GPU-driven rendering (indirect draw, GPU culling) | Extends `ke_render` |
| Real-time GI (DDGI / Lumen-class) | Long-term R&D |
| Ray tracing | Architectural decision needed — bgfx doesn't expose RT, may require backend swap (see Kanban Parking Lot `[F.GPU]`) |

---

## Architectural directions *(post-1.0, parking-lot)*

Long-term doctrines being actively designed. None shipping in M1–M5 unless the underlying milestone forces them.

- **Concurrency by construction** — phantom thread tokens + forward-only queues + API-by-absence. Goal: deadlocks and cross-thread races structurally unrepresentable. See Kanban `[DEADLOCK-FREE]`.
- **Marketplace compatibility contracts** — small composable gameplay-layer interfaces (`IDamageable`, `IInteractable`, `IInventoryHost`, etc.) that let third-party kits compose without inheritance traps. See Kanban Parking Lot `[GAMEPLAY-CONTRACTS]`.
- **GpuDevice backend swap** — bgfx replacement (The Forge / Diligent Engine) only when ray tracing or mesh shaders force the issue. See Kanban Parking Lot `[F.GPU]`.

---

*This file is a snapshot, not a contract.* Priorities shift as examples reveal real ergonomic gaps. The authoritative living list is `Kanban.md` (internal); this page exists so external readers can see the shape of what's coming without reading the full board.
