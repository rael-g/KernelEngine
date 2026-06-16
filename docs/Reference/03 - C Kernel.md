# C Kernel

The kernel (`src/c/kernel/`) is the ABI-stable heart of the engine. Pure C, `extern "C"`, vtable-style function pointers everywhere. Public headers live under each domain's `include/` (e.g. `src/c/logger/include/`, `src/c/ecs/include/`); no `ke_kernel` meta-target exists — consumers link specific impl targets directly.

Conventions: `snake_case` with a `ke_` prefix; `ke_result` return values with optional `ke_error** out_error` (no exceptions — see §"Error handling" below); `_params` suffix for parameter-bag structs (never `_desc`/`_info`/`_config`); `#pragma once`. `ke_allocator` is an **internal** implementation utility — not passed as a factory parameter (see `docs/Development/ProjectGuidelines.md` §1.4).

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

### `ke_allocator` (internal utility)
Internal memory abstraction used by all C domain implementations. **Not a public API; not passed as a factory parameter.** Implementations link `ke_allocator_malloc` (or `arena`, `proxy`) as a PRIVATE CMake dep. The single point of change for the underlying heap strategy is `src/c/allocator/malloc/src/allocator_malloc.c`. In debug builds, impls link `ke_allocator_proxy` and report leaks in their `destroy()`.

### Error handling — `ke_result` + `ke_error` + `ke_error_type`

Every fallible operation returns `ke_result` (a two-value enum: `KE_OK = 0` / `KE_ERROR = -1`) and optionally writes a `ke_error*` to a caller-provided output pointer. The kernel never throws.

```c
// error.h — minimalista, controle de fluxo apenas
typedef enum ke_result { KE_OK = 0, KE_ERROR = -1 } ke_result;

// ke_error_type — singleton global; comparação por identidade de ponteiro (não por int)
typedef struct ke_error_type {
    const char*                  name;    // "ke.window.not_initialized"
    const struct ke_error_type*  parent;  // categoria genérica, ou NULL
} ke_error_type;

// ke_error — contexto rico, preenchido no ponto de origem
typedef struct ke_error {
    const ke_error_type* type;
    const char*          message;  // detalhe dinâmico, string human-readable
    const char*          domain;   // "ke_window", "ke_ecs", etc.
} ke_error;
```

**Categorias genéricas** são declaradas em `error.h`:

```c
extern const ke_error_type KE_ERROR_NOT_FOUND;
extern const ke_error_type KE_ERROR_IO;
extern const ke_error_type KE_ERROR_OUT_OF_MEMORY;
extern const ke_error_type KE_ERROR_INVALID_ARGUMENT;
extern const ke_error_type KE_ERROR_NOT_INITIALIZED;
extern const ke_error_type KE_ERROR_NOT_SUPPORTED;
extern const ke_error_type KE_ERROR_ALREADY_EXISTS;
```

**Tipos por domínio** são declarados em `<domain>/error.h`, com `parent` apontando para a categoria genérica correspondente (ou NULL para erros sem categoria genérica equivalente):

```c
// ke_window/error.h
extern const ke_error_type KE_WINDOW_ERROR_NOT_INITIALIZED;   // parent: NULL
extern const ke_error_type KE_WINDOW_ERROR_CREATION_FAILED;   // parent: &KE_ERROR_IO
```

**Assinatura de vtable:** o parâmetro `out_error` é sempre opcional — `NULL` é válido quando o caller não precisa de contexto:

```c
ke_result (*load)(ke_scene_loader* self, const char* path, ke_error** out_error);
```

**Matching com hierarquia:**

```c
bool ke_error_is(const ke_error* err, const ke_error_type* type);

// caller escolhe o nível de granularidade:
if (ke_error_is(err, &KE_WINDOW_ERROR_NOT_INITIALIZED)) { /* específico */ }
if (ke_error_is(err, &KE_ERROR_IO)) { /* qualquer IO de qualquer domínio */ }
```

**Memória:** `ke_error` aponta para um buffer thread-local estático preenchido pelo callee. Zero alocação no caminho de erro. O ponteiro é válido até a próxima chamada que falha na mesma thread — o caller deve consumir imediatamente.

O managed layer mapeia `ke_result` + `ke_error` para `KernelResult` / `Result<T>` / `KernelException`.

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
