# C Kernel

The kernel (`src/c/kernel/`) is the ABI-stable heart of the engine. Pure C, `extern "C"`, vtable-style function pointers everywhere. Public headers live under `src/c/kernel/include/kernel_engine/kernel/`; private implementation under `src/`. CMake target: `ke_kernel` (alias `ke::kernel`).

Conventions: `snake_case` with a `ke_` prefix; `ke_result` return values (no exceptions); explicit `ke_allocator*` for anything that allocates; `_params` suffix for parameter-bag structs (never `_desc`/`_info`/`_config`); `#pragma once`.

## Module map

```
include/kernel_engine/kernel/
├── common/      hash, hash_map, array, error (ke_result), math, handles
├── context/     allocator (ke_allocator), types
├── logger/      logger (ke_logger, ke_logger_sink), log_level
├── world/       ecs (ke_ecs_registry), system, world (ke_world), components
├── engine/      frame, frame_packet (ke_frame_packet)
├── render/      render (ke_render), light, mesh, material, texture, shader_compiler
├── window/      window (ke_window)
├── input/       input, snapshot (ke_input_snapshot)
├── asset/       asset_loader (ke_asset_loader), mesh_data
├── threading/   thread (ke_thread), semaphore (ke_semaphore), frame_sync (ke_frame_sync)
├── task_scheduler/  task_scheduler (ke_task_scheduler)
└── dev_platform/    dev_platform (ke_dev_platform)
```

## Foundations

### `ke_allocator` ✅
The explicit allocator contract passed to every major component. Built-in strategies: malloc and arena. There is no implicit global heap (Principle 6). Raw pointers are non-owning unless documented.

### `ke_result` & error handling ✅
Every fallible operation returns a `ke_result`. Callers must handle it; the kernel never throws. The managed layer maps this to `KernelResult` / `Result<T>`.

### `ke_logger` / `ke_logger_sink` ✅
Pluggable logging. The kernel defines the contract and log levels; sinks (console, Serilog) are provided by higher layers.

### `common/` primitives ✅
Hash, hash map, growable array, math helpers, and typed `handles`. These are the data-structure building blocks shared across kernel modules.

## ECS & world

### `ke_ecs_registry` ✅
A **sparse-set ECS**. Entities (`ke_entity`, a `uint64_t`) map to component storage. Supports register-component, add/get/remove component, and queries that yield packed spans for cache-friendly iteration. This is the data-oriented backbone the render/transform systems iterate.

### `ke_world` ✅
Owns the ECS registry and the system graph. Creates entities/nodes (name + transform + hierarchy components) and drives the per-frame update.

### `system` (the system graph) ✅
A system contract carries: name, an update function, and declared **reads[]/writes[]** component access. The kernel performs conflict analysis on those access sets to build parallel **waves** of non-conflicting systems, dispatched via the task scheduler. Systems that write the same component are serialized automatically.

> The scheduler cares only about *data dependencies*, not the language of each system — a C# system passing a `delegate* unmanaged` is scheduled alongside native systems (one P/Invoke per frame, acceptable for non-per-entity game logic).

### Built-in components ✅
Transform, hierarchy, name, and a script component (carrying `on_start`/`on_update` callbacks for scripted entities). These are kernel-level because the transform/hierarchy systems are universal.

## Cross-thread contracts

These are the **only** channels by which data crosses thread boundaries — never shared mutable state.

### `ke_frame_packet` ✅
A per-frame snapshot written by the simulation and consumed by the renderer. The sole sim→render communication channel: camera, lights, skybox, draw commands, shadow draw commands, post-processing settings. Draw arrays use `atomic_fetch_add` on the count so multiple systems record in parallel without locks.

### `ke_input_snapshot` ✅
An immutable capture of input state, produced once per OS tick and consumed by the simulation at the start of each world update. The sim reads a frozen, consistent view of input for the whole frame.

### `ke_frame_sync`, `ke_thread`, `ke_semaphore` ✅
Threading **primitives** — not a threading *model*. `ke_frame_sync` is a double-buffer ring for producer/consumer handoff; `ke_thread` and `ke_semaphore` are the OS-thread and signaling primitives. The kernel imposes no threading model; the 3-thread arrangement is a framework decision (see [08 - Multithreading](08%20-%20Multithreading.md)).

### `ke_task_scheduler` ✅
Contract for a parallel task scheduler (implemented by the enkiTS plugin). Used for the wave-based parallel system execution and any fork/join work.

## Capability contracts (vtables, implemented by plugins)

The kernel **declares** these and never implements them. Plugins satisfy them.

| Contract | Purpose | Backend plugin |
|---|---|---|
| `ke_render` | Renderer: GPU resources, draw submission, view config | bgfx |
| `ke_window` | Window + OS event surface | GLFW |
| `ke_asset_loader` | Load models (mesh/material/texture data) | Assimp |
| `ke_shader_compiler` | Compile shader sources to GPU binaries | shaderc (bgfx) |
| `ke_dev_platform` | Dev-only OS facilities (thread naming; future: crash handler) | Win32 (🚧 Win32 only) |

Render-domain support types the contract uses: `ke_mesh`, `ke_material`, `ke_texture`, `ke_light`, plus `ke_vertex` (the standard vertex layout: position, normal, UV, tangent) and `mesh_data` for loaded geometry.

## What is deliberately NOT in the kernel

Per Principle 2, the kernel has **no** concrete systems or features: no specific renderer, no health/gameplay systems, no scene-file format, no node paradigm, no post-processing chain. Those live in plugins (C++) or the framework (C#). The render systems themselves are pure-managed C# in the framework today (see [07 - Graphics & Rendering](07%20-%20Graphics%20%26%20Rendering.md)).
