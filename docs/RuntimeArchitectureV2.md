# Runtime Architecture V2 — `ke_runtime` Contract Design

**Status**:
- §3 (C ABI contract) — vtable shape, Module/System lifecycle, Phase enum locked.
- §4–§15 — Locked at design level.
- **Architectural shape (settled after R2.5 storage/scheduler separation discussion)**:
  - `ke_runtime` and `ke_ecs` are **separate, focused contracts**. Different plugins satisfy each; runtime never owns storage.
  - **`ke_runtime` (scheduler + orchestration) is our code.** Bevy-style parallel waves from declared R/W metadata, dispatch through `ke_task_scheduler*` (enkiTS), barriers per wave, deferred command queue, fixed-timestep accumulator. No third-party scheduler.
  - **`ke_ecs` (storage + queries) is satisfied by `KernelEngine.Ecs.Flecs`** — a thin C ABI wrapper over flecs's storage half. flecs is compiled with `FLECS_PIPELINE` / `FLECS_SYSTEM` / `FLECS_TIMER` disabled — the scheduler code physically isn't in the binary.
  - **No process-global state.** flecs's `ecs_os_api` is not modified. N runtimes per process are valid; each owns its own flecs world.
  - The runtime plugin depends on `ke_ecs*` injected via factory (the "simple runtime accepts external ECS" pattern from earlier drafts — now the real shape, not a hypothetical alternative).
- R1/R2 commits (`b58b21f`, `87001a0`, `e3fba2a`, `df48365`) validated the C ABI shape, the binding pattern, and the flecs 4.1.5 upgrade. The plugin layout pivots from R2.5 onward to reflect the storage/scheduler split.
**Audience**: Engine maintainer + future plugin authors (renderer / physics / audio / scripting).
**Companion doc**: [`RenderArchitectureV2.md`](RenderArchitectureV2.md).

---

## 1. Purpose

The engine is currently a **set of APIs without a brain**. The C kernel exposes contracts (`ke_render`, `ke_window`, `ke_input`, `ke_ecs`); the host (C# `Application.cs` or hand-rolled Lua main loop) wires everything together and drives the frame loop. This pushes the **orchestration responsibility back to every game**, which:

- Bloats `Application.cs` (already large, will grow with each plugin)
- Forces every binding language (Lua spike, future Rust binding) to re-implement the orchestration glue
- Makes the engine name (`KernelEngine`) inaccurate — a kernel has a scheduler; ours doesn't
- Couples module ordering / lifecycle / thread affinity to host code instead of declaring it in the engine

**This document defines `ke_runtime`** — a C-ABI contract for a scheduler-centric runtime. A runtime owns the simulation orchestration: schedules systems with dependency ordering, dispatches work to the shared `ke_task_scheduler` worker pool, and extracts a frame snapshot for the render thread. The host becomes a **declarative wiring layer**: it instantiates modules and starts the runtime. The runtime runs the game.

**Design principle — focused contracts, no mandatory marriage**: `ke_runtime` declares scheduler/orchestration. `ke_ecs` declares storage/query. Runtime depends on `ke_ecs*` injected at construction; it never owns storage. This keeps both replaceable: a future custom ECS (different storage model) drops in without touching the runtime; a future custom scheduler (different parallelism strategy) drops in without touching the ECS.

**The implementations we build**:

- **`KernelEngine.Runtime`** (`src/c/runtime/`) — the runtime. Algorithm: Bevy-style scheduler — phases run in order; within a phase, systems group into parallel waves by R/W conflict; each wave dispatches through `ke_task_scheduler*` (enkiTS); barrier per wave; deferred command queue flushed at wave boundaries; fixed-timestep accumulator for `FixedUpdate`. Pure orchestration code; no third-party scheduler embedded.
- **`KernelEngine.Ecs.Flecs`** (`src/c/ecs/flecs/`) — the storage. Thin C ABI wrapper over flecs's storage half. flecs is built with `FLECS_PIPELINE` / `FLECS_SYSTEM` / `FLECS_TIMER` disabled — the scheduler addons aren't compiled in. We use flecs purely for: archetype storage, component lifecycle, query matching, iteration, hierarchies (parent/child), pairs/relationships, observers (`OnAdd`/`OnRemove`/`OnSet`).

Why this split (full rationale in §8):

- flecs's storage is excellent and gives us hierarchies + pairs + observers for free — irreplaceable today.
- flecs's scheduler injection points (`ecs_os_api`) are process-global, not per-instance — incompatible with the kernel's freedom-first doctrine of per-instance components.
- Writing our own scheduler isn't a sacrifice; it's the path that makes the runtime + ECS contracts genuinely independent. Anyone replacing flecs (with EnTT, gaia, or a custom sparse-set ECS) only swaps the storage plugin — the scheduler keeps working.

---

## 2. Core concepts

The contract introduces five concepts. They map cleanly onto Bevy's vocabulary and flecs's primitives.

### 2.1 Runtime

The top-level orchestrator. Owns:
- A simulation **World** (component storage + entities + queries)
- A **Scheduler** that dispatches systems across the thread pool
- The list of **Modules** loaded
- The set of **Resources** (singleton typed slots — `Time`, `WindowSize`, etc.)
- The frame loop itself

One `ke_runtime*` per game. Lifetime = game lifetime.

### 2.2 Module

A self-contained unit of engine functionality. A module **declares**:
- Which components it registers
- Which systems it adds to which scheduler phases
- Which resources it provides
- Which other modules it depends on (load-order constraint)

Examples: `KernelEngine.Render.Module` registers `MeshComponent`, `MaterialComponent`, the `MeshRenderSystem`. `KernelEngine.Physics.Box2D.Module` registers `Body2DComponent`, the `PhysicsStepSystem`. The Pong game itself is **just another module** that registers `PaddleComponent` + `PaddleControlSystem`.

Modules are loaded in dependency order at runtime startup. Once loaded, they never unload (no hot-swap in V2; consider for V3 hot-reload).

### 2.3 System

A function executed by the scheduler. A system declares:
- **Read set**: components it reads
- **Write set**: components it writes
- **Resource access**: which singleton resources it reads/writes
- **Phase**: which scheduler phase it runs in
- **Dependencies**: explicit "runs after X" / "runs before Y"

The scheduler uses read/write sets to infer parallelism (two systems with disjoint write sets run in parallel; conflicting writes serialize). Explicit dependencies override.

### 2.4 Scheduler

The runtime-internal component that decides system execution order each tick. Bevy-style algorithm, dispatches through the engine-wide enkiTS pool (see §6, §8).

The scheduler runs **phases** in fixed order:
- `Startup` (once)
- `PreUpdate` (every tick)
- `FixedUpdate` (0..N times per tick — fixed-dt physics step, "Fix Your Timestep" accumulator pattern)
- `Update` (every tick — variable dt)
- `PostUpdate` (every tick)
- `Extract` (every tick — copies sim state into the frame packet)
- `Shutdown` (once)

`FixedUpdate` runs at a deterministic timestep (default 1/60s) regardless of frame rate. The runtime accumulates real elapsed time and runs `FixedUpdate` 0, 1, or N times per `tick()` to catch up. Standard pattern across Unity / Godot / Bevy; mandatory for stable physics (Box2D `world->Step(fixed_dt)`).

Within a phase the scheduler computes **parallel waves**: a greedy walk over registered systems (in declaration order) grouping mutually-compatible systems into the same wave. Two systems are compatible iff their declared component-access sets don't conflict (no write-write, no write-read on the same component, no overlap of declared resource writes). Wave execution: enqueue one enkiTS task per system in the wave, barrier on completion, flush deferred commands accumulated by systems in the wave, advance to next wave. Between phases, all waves of the current phase complete before the next phase starts.

Systems without declared R/W metadata are treated as **exclusive** (their own wave, alone). Safe conservative default — they don't break parallelism for declaring neighbors; they just don't benefit from it.

### 2.5 Resource

A typed singleton owned by the runtime. Distinguished from components (which live per-entity). Examples:
- `Time { float dt; uint64_t frame; }`
- `WindowSize { int w, h; }`
- `InputSnapshot { ... }` (replaces our current `ke_input_snapshot` mechanism)

Systems request resources by type, get a typed handle. Read/write contention on resources participates in scheduler parallelism the same way components do.

---

## 3. C ABI — `ke_runtime` contract  *(Accepted, locked)*

> **Ratification note (2026-06-XX, R1 spike)**: a minimal subset of the surface below (`register_module`, `register_system` for `KE_PHASE_UPDATE`, `tick`, `destroy`) was implemented in `src/c/runtime/flecs/` and exercised end-to-end by 5 integration tests (commit `b58b21f`). The vtable shape, struct-by-`params` pattern, and Module/System lifecycle were validated against flecs's actual API; no rework of the contract surfaced. Resources, full phase pipelines (FixedUpdate / Extract / Startup / Shutdown), and dependency ordering (`runs_after` / `runs_before`) are locked at design level and expected to land cleanly in R2+.

> **Spike findings worth carrying forward** (for the future agent who continues the impl):
> - flecs's `ecs_entity(world, {...})` / `ecs_ids(...)` macros expand to compound literals that our clang's C99 mode rejects. Use the raw `ecs_entity_init` / `ecs_system_init` API and write directly into `ecs_entity_desc_t::add[i]`.
> - `alignof` in C requires `<stdalign.h>`.
> - `KE_ERROR_INVALID_STATE` does not exist in `error.h`. R1 used `KE_ERROR_NOT_INITIALIZED`; consider adding `INVALID_STATE` if a clearer slot is needed later.

Lives at `src/c/kernel/include/kernel_engine/kernel/runtime/runtime.h`.

```c
// Opaque types — every concrete runtime carries its own state behind `handle`.
typedef struct ke_runtime          ke_runtime;
typedef struct ke_module           ke_module;
typedef struct ke_system           ke_system;
typedef struct ke_resource_handle  ke_resource_handle;

// IDs returned by the runtime; bindings treat them as opaque.
typedef uint64_t ke_module_id;
typedef uint64_t ke_system_id;

// Phases — fixed enum, scheduler enforces order.
typedef enum ke_phase {
    KE_PHASE_STARTUP      = 0,
    KE_PHASE_PRE_UPDATE   = 1,
    KE_PHASE_FIXED_UPDATE = 2,  // 0..N times per tick, fixed dt
    KE_PHASE_UPDATE       = 3,  // every tick, variable dt
    KE_PHASE_POST_UPDATE  = 4,
    KE_PHASE_EXTRACT      = 5,
    KE_PHASE_SHUTDOWN     = 6,
} ke_phase;

// Access kind — used in read/write set declarations.
typedef enum ke_access {
    KE_ACCESS_READ      = 1 << 0,
    KE_ACCESS_WRITE     = 1 << 1,
} ke_access;
```

### 3.1 Runtime vtable

```c
typedef struct ke_runtime {
    void *handle;  // impl-private state

    // ── Module registration (called during startup, before run() ─────────────
    ke_result (*register_module)(ke_runtime *self, const ke_module_params *params,
                                 ke_module_id *out_id);

    // ── Resource management ─────────────────────────────────────────────────
    ke_result (*register_resource)(ke_runtime *self, const char *type_name,
                                   size_t size, ke_resource_handle *out_handle);
    void *    (*get_resource)(ke_runtime *self, ke_resource_handle handle);

    // ── World access ────────────────────────────────────────────────────────
    // Exposes the underlying ke_ecs world so existing code (which uses
    // ke_ecs_component_register_v2, ke_ecs_component_get, etc.) keeps working.
    struct ke_world * (*get_world)(ke_runtime *self);

    // ── System registration ─────────────────────────────────────────────────
    ke_result (*register_system)(ke_runtime *self, const ke_system_params *params,
                                 ke_system_id *out_id);

    // ── Frame loop ──────────────────────────────────────────────────────────
    // Drives one full tick: PreUpdate → Update → PostUpdate → Extract.
    // Returns KE_OK on normal tick, KE_RESULT_SHUTDOWN if the runtime decided
    // to stop (e.g. window closed event observed in a system).
    ke_result (*tick)(ke_runtime *self, float dt);

    // Runs Startup once, then ticks until tick() returns KE_RESULT_SHUTDOWN
    // or an external cancellation signal fires.
    ke_result (*run)(ke_runtime *self, ke_runtime_cancel_token *cancel);

    // ── Snapshot extraction ─────────────────────────────────────────────────
    // After the Extract phase, the runtime hands the consumer (render thread)
    // a borrowed pointer to the frame packet. Pointer is valid until the next
    // tick() / run() iteration.
    const ke_frame_packet * (*peek_frame_packet)(ke_runtime *self);

    // ── Lifecycle ───────────────────────────────────────────────────────────
    void (*destroy)(ke_runtime *self);
} ke_runtime;
```

### 3.2 Module params

```c
typedef struct ke_module_params {
    const char *name;                 // "KernelEngine.Render", "Pong", etc.
    const char **dependencies;        // null-terminated list of module names
    void *user_data;                  // forwarded to the on_load callback

    ke_result (*on_load)(ke_runtime *runtime, void *user_data);
    void      (*on_unload)(ke_runtime *runtime, void *user_data);
} ke_module_params;
```

`on_load` is where a module registers its components, systems, resources. Called by the runtime during startup, in dependency order. `on_unload` is called once during shutdown.

### 3.3 System params

```c
typedef struct ke_component_access {
    ke_component_id  cid;
    ke_access        access;          // READ, WRITE, or READ|WRITE
} ke_component_access;

typedef struct ke_system_params {
    const char *name;                 // for debugging / Tracy zone naming
    ke_phase    phase;

    const ke_component_access *access_list;
    uint32_t                   access_count;

    const ke_resource_handle  *resource_reads;
    uint32_t                   resource_read_count;
    const ke_resource_handle  *resource_writes;
    uint32_t                   resource_write_count;

    const ke_system_id *runs_after;   // explicit ordering
    uint32_t            runs_after_count;
    const ke_system_id *runs_before;
    uint32_t            runs_before_count;

    bool   exclusive;                 // when true, runs in own wave (conflicts with all)
    void  *user_data;
    void (*execute)(ke_system_ctx *ctx, void *user_data, float dt);
} ke_system_params;
```

System functions are plain C function pointers — same `[UnmanagedCallersOnly]` bridge pattern we already use for script callbacks. The execute callback gets a `ke_system_ctx*` (the doorway defined in §15.8) — **the only path to component memory inside the system body**. The `dt` is the timestep. Note: the spike (R1/R2) used `(ke_runtime*, void*, float)`; that shape is superseded by §15.8 and migrates during R2.5c.

### 3.4 Factory

The runtime is a single plugin; the ECS is a separate plugin. Each has its own factory. The runtime factory accepts a `ke_ecs*` borrowed from the storage plugin — that's how the two contracts compose at runtime without coupling at the type level.

**Runtime factory** (lives in `src/c/runtime/include/kernel_engine/kernel/runtime/runtime_create.h`):

```c
KE_API ke_result ke_runtime_create(
    ke_allocator             *alloc,
    ke_ecs                   *ecs,             // borrowed; storage plugin provides
    ke_task_scheduler        *task_scheduler,  // borrowed; enki plugin provides
    const ke_runtime_params  *params,
    ke_runtime              **out_runtime);
```

`ke_runtime_params` carries phase configuration (fixed timestep dt, max accumulator catch-up, custom phase list if any), logger pointer, and other knobs. Empty `{0}` is valid (sane defaults).

**ECS factory** (lives in `src/c/ecs/flecs/include/kernel_engine/kernel/ecs/flecs/ecs_flecs_create.h`):

```c
KE_API ke_result ke_ecs_flecs_create(
    ke_allocator              *alloc,
    const ke_ecs_flecs_params *params,
    ke_ecs                   **out_ecs);
```

The flecs ECS plugin owns its own `ecs_world_t` internally. The caller hands it to the runtime via `ke_runtime_create(..., ecs, ...)`. Anyone else (asset loader, scene tree, ad-hoc queries) can also hold the same `ke_ecs*` — there's no exclusivity.

**C# DI registration** (typical host):

```csharp
services.AddKernel()
        .AddEnkiTaskScheduler()
        .AddFlecsEcs()
        .AddRuntime();
```

Each `Add*` resolves the previous dependencies and registers the next one. The runtime's DI registration depends on `IEcs` and `ITaskScheduler` being registered first; DI throws if not. Composition is explicit, not magical.

**Common doctrine across all factories**: borrowed dependencies (`ke_ecs*`, `ke_task_scheduler*`, `ke_allocator*`) outlive every consumer. Lifetime contract: the host arranges destruction in reverse order — runtime first, then ECS, then task scheduler, then allocator.

### 3.5 C# sugar layer — Bevy-style systems via source generator

The C ABI keeps the explicit `access_list` because C has no introspection and dynamic-language bindings (Lua, Python) cannot infer anything from a callback signature. **This is a contract-level necessity, not a defect.**

But the C# binding has Roslyn — analyzers + source generators that run at build time, zero runtime cost. The C# surface MUST hide the explicit access list and let game devs write systems Bevy-style:

```csharp
[System(Phase.Update)]
static void PaddleSystem(
    Query<Mut<Transform>, With<Paddle>> paddles,
    Res<Time> time,
    Res<InputState> input)
{
    foreach (var (transform, _) in paddles) {
        if (input.Value.IsPressed(MoveAction.Up))
            transform.Value.Position.Y += 5f * time.Value.dt;
    }
}
```

**At build time**, a source generator inspects every `[System]`-attributed method:
- Parameter `Query<Mut<T>, ...>` → `KE_ACCESS_WRITE` on T's component id
- Parameter `Query<T, ...>` (no `Mut`) → `KE_ACCESS_READ` on T's component id
- Parameter `Res<T>` → resource read of T
- Parameter `ResMut<T>` → resource write of T
- Parameter `With<T>` / `Without<T>` → query filter, not an access entry

The generator emits a `_<MethodName>_Wrapper` (typed `void (ke_runtime*, void*, float)`) that resolves queries/resources and calls the user function, plus a static `_<MethodName>_Params` initializer matching the C `ke_system_params` struct. Module load code registers the params with the runtime.

A companion **Roslyn analyzer** enforces use at compile time:
- Trying to mutate a `Query<Transform>` parameter (without `Mut`) → red squiggle: "system declared read-only access to Transform; wrap in `Mut<Transform>` to write"
- Trying to access a resource not in the parameter list → red squiggle: "system did not declare resource access for X"
- Two systems with conflicting writes in the same phase without a dep declaration → warning at registration time

This delivers Bevy's "if it compiles, it's correctly scheduled" guarantee at the C# layer **without** changing the C ABI.

**Module declaration follows the same shape**:
```csharp
[Module("KernelEngine.Render")]
[DependsOn("KernelEngine.Window")]
public static partial class RenderModule
{
    [OnLoad]
    static void OnLoad(IRuntime runtime) { /* register components, resources */ }

    // [System] methods declared in this class auto-register on module load
}
```

Source generator scans the class, emits `ke_module_params` + the `on_load` glue that registers every `[System]` method found. Dev never touches the C ABI.

**Lua and other dynamic bindings** declare explicitly through their respective sugar — no codegen available. The C ABI is the lowest common surface; C# happens to be able to do better than the surface lets on.

A concrete example: how `KernelEngine.Render` registers itself.

```c
// src/cpp/render/module/render_module.cpp (sketch)

static void mesh_render_system_execute(ke_runtime *rt, void *ud, float dt) {
    auto *world = rt->get_world(rt);
    // existing MeshRenderSystem logic, unchanged
}

static ke_result render_module_on_load(ke_runtime *runtime, void *ud) {
    auto *world = runtime->get_world(runtime);

    // Register components via existing ke_ecs API
    auto mesh_cid     = ke_ecs_component_register_v2(world, "Mesh",  sizeof(MeshComponent),  /* ... */);
    auto material_cid = ke_ecs_component_register_v2(world, "Material", sizeof(MaterialComponent), /* ... */);

    // Register render-only resources
    ke_resource_handle frame_packet_h;
    runtime->register_resource(runtime, "FramePacket", sizeof(ke_frame_packet), &frame_packet_h);

    // Register the MeshRenderSystem in the Extract phase
    ke_component_access access[] = {
        { mesh_cid,     KE_ACCESS_READ },
        { material_cid, KE_ACCESS_READ },
    };
    ke_system_params sys = {
        .name = "MeshRenderSystem",
        .phase = KE_PHASE_EXTRACT,
        .access_list = access,
        .access_count = 2,
        .resource_writes = &frame_packet_h,
        .resource_write_count = 1,
        .execute = mesh_render_system_execute,
    };
    ke_system_id sid;
    runtime->register_system(runtime, &sys, &sid);

    return KE_OK;
}
```

Bindings (C#, Lua) declare the same shape through thin wrappers. C# `Module` interface example:

```csharp
public interface IModule {
    string Name { get; }
    IReadOnlyList<string> Dependencies { get; }
    void OnLoad(IRuntime runtime);
    void OnUnload(IRuntime runtime);
}

// Registration via DI:
services.AddRuntime<FlecsRuntime>()
        .AddModule<RenderModule>()
        .AddModule<PhysicsModule>()
        .AddModule<PongModule>();
```

`Application.cs` evaporates. `Program.cs` is the entire host:

```csharp
var builder = new RuntimeBuilder();
builder.UseRuntime<FlecsRuntime>()
       .AddModule<RenderModule>()
       .AddModule<Box2DPhysicsModule>()
       .AddModule<PongModule>();

using var runtime = builder.Build();
runtime.Run();
```

---

## 5. Lifecycle

```
                  ┌──────────────────────────────────────────────┐
                  │  runtime_create()                            │
                  └──────────────────┬───────────────────────────┘
                                     ↓
                  ┌──────────────────────────────────────────────┐
                  │  register_module(...) ×N                     │
                  │  → modules sorted by dep order               │
                  └──────────────────┬───────────────────────────┘
                                     ↓
                  ┌──────────────────────────────────────────────┐
                  │  run() → executes Startup phase              │
                  │  → every module.on_load() called, registers  │
                  │    components/systems/resources              │
                  │  → every Startup-phase system runs once      │
                  └──────────────────┬───────────────────────────┘
                                     ↓
                  ┌─────────────────────────────────────────────┐
                  │  Frame loop (until cancel/shutdown):         │
                  │   tick(dt):                                  │
                  │     PreUpdate    ─→ scheduler runs systems   │
                  │     FixedUpdate ×N ─→ accumulator pattern:   │
                  │                       run until caught up    │
                  │                       to wall-clock at       │
                  │                       fixed dt (default 1/60)│
                  │     Update       ─→ variable dt              │
                  │     PostUpdate   ─→ scheduler runs systems   │
                  │     Extract      ─→ writes ke_frame_packet   │
                  │   render thread reads packet via             │
                  │   peek_frame_packet() and draws              │
                  └──────────────────┬──────────────────────────┘
                                     ↓
                  ┌──────────────────────────────────────────────┐
                  │  Shutdown phase runs (systems then           │
                  │  module.on_unload())                         │
                  └──────────────────┬───────────────────────────┘
                                     ↓
                  ┌──────────────────────────────────────────────┐
                  │  destroy()                                   │
                  └──────────────────────────────────────────────┘
```

---

## 6. Threading model

**Two named threads** (down from three):
- `ke.sim` — runs the runtime tick loop (which internally dispatches systems across workers)
- `ke.render` — consumes the frame packet and submits draws

`ke.main` (window/input polling) is folded into `ke.sim`. GLFW poll runs at the top of each tick before the scheduler dispatches.

**Worker pool**: single shared `ke_task_scheduler` (enkiTS). The runtime's wave dispatcher submits tasks directly to it — no other thread machinery is created anywhere. flecs is built without its pipeline addon (`FLECS_PIPELINE` off), so flecs's threading API is not even compiled in. Other engine subsystems (asset loading, PSO compile, audio mixing) dispatch to the same pool. One pool, one source of parallelism.

**Synchronization at the sim/render boundary**: the runtime owns `ke_frame_packet` as a registered resource. The Extract phase writes it; immediately after Extract completes, the runtime signals the render thread (semaphore inside `ke_runtime`). Render reads via `peek_frame_packet()`, runs its pipeline, signals back when done. **No frame-sync object on the host side** — the runtime owns the handshake.

This formalizes what we already do but moves the coordination from `Application.cs` (host) into the runtime (engine). Bindings get it for free.

---

## 7. Sim → Render extraction boundary

Bevy's `ExtractSchedule` is the model. Our `KE_PHASE_EXTRACT` does the same job:

- Runs **after** `PostUpdate` completes (all simulation state for this frame is final)
- Runs **before** the render thread is unblocked
- Systems in `Extract` phase **only read sim components** and **only write the frame packet** (or other render-bound snapshots)
- Read/write set declarations are scheduler-enforced — an Extract system that tries to mutate a sim component triggers a debug assertion

The frame packet ABI stays compatible with what we have today (`ke_frame_packet`) — the change is that now it's a **runtime resource**, not a host-managed object.

---

## 8. Scheduler + threading doctrine — our scheduler, flecs storage-only

### 8.1 The decision (and what got rejected)

We evaluated four ways to wire ECS + scheduling + pool:

- **(A) flecs pipeline + `ecs_os_api` bridge to enki**. flecs runs its scheduler; the global `ecs_os_api.task_new_/task_join_` slots are overridden to dispatch through enki. Pool unified. **Rejected**: `ecs_os_api` is process-global, not per-world — forces a "1 flecs runtime per process" constraint we don't want; the thread-shaped flecs API doesn't compose cleanly with a task-shaped pool (heap-alloc fake handles per task); the calling thread blocks cluelessly in `task_join_` instead of work-stealing on the shared pool. Singleton dialect carried forever.
- **(B) flecs pipeline single-threaded, enki for everything else**. Disable flecs parallelism; engine subsystems use enki explicitly. **Rejected**: capitulates on ECS parallelism for the wrong reason.
- **(C) Oversubscription**: flecs spawns N pthreads, enki has M workers, OS arbitrates. **Rejected**: obviously bad.
- **(D) Our scheduler, flecs storage-only**. Build with `FLECS_PIPELINE` off. Use flecs purely for archetype storage, queries, iteration, hierarchies, pairs, observers. Write our own Bevy-style scheduler in C that dispatches through `ke_task_scheduler*` (enki). **Chosen.**

Why D won on the harmonia axis: A buys high internal flecs↔flecs harmony (gift work — beautiful) but pays low external harmony forever (a flecs dialect island inside an engine that's otherwise ke-shaped). D builds external harmony (runtime ↔ ECS ↔ rest-of-engine all in the same idiom) and accepts lower internal harmony (we built the seam between scheduler and storage instead of inheriting it). External harmony travels with every subsystem we add; internal flecs↔flecs harmony stays trapped inside the flecs corner. We chose the harmony that scales.

### 8.2 The scheduler we build

Pure-C in `src/c/runtime/src/scheduler/`. ~600-800 LoC across:

- **wave_builder.c** — greedy R/W conflict grouping. Given an ordered list of systems with declared `(reads, writes)` sets, emit a list of waves (each wave = list of mutually compatible systems). Bevy's algorithm, no magic.
- **dispatcher.c** — wave execution: enqueue one enki task per system in the wave (each task calls `system->execute(runtime, user_data, dt)`), block on `enki_wait_for_wave()`, flush deferred commands, advance.
- **phase_loop.c** — Startup once, then per-tick PreUpdate → FixedUpdate ×N (accumulator) → Update → PostUpdate → Extract. Shutdown on destroy. Each phase: walk waves, dispatch, barrier.
- **defer_queue.c** — per-wave command queue. Systems running in parallel mutate via this queue (`spawn`, `add_component`, `remove_component`, `destroy_entity`). Queue applied serially at wave barrier through the `ke_ecs*` C ABI.
- **timestep.c** — Glenn Fiedler's "Fix Your Timestep" accumulator for `FixedUpdate`.

R/W metadata declaration is **explicit at registration** — same shape flecs C requires (`.inout = EcsIn` per query term). The scheduler reads `ke_system_params.access_list`. Systems that don't declare access are marked exclusive (their own wave, single-threaded).

### 8.3 What flecs does for us (storage-only)

flecs is compiled with these `#define` flags removed: `FLECS_PIPELINE`, `FLECS_SYSTEM`, `FLECS_TIMER`. The scheduler code physically isn't linked. What remains:

| Capability | Provided by flecs | Used by |
|---|---|---|
| Archetype storage (SoA per archetype) | core | every component access |
| Entity ID + generation | core | every entity reference |
| Component lifecycle (add/remove triggers archetype migration) | core | runtime + game code |
| Query matching (find archetypes containing `{A,B,C}`) | core | system execute bodies |
| Query iteration (yield packed slices) | core | system execute bodies |
| Hierarchies (parent/child via `EcsChildOf`) | core | scene tree |
| Pairs / relationships (e.g. `(Likes, Bob)`) | core | future gameplay (AI, inventory, factions) |
| Observers (`OnAdd`, `OnRemove`, `OnSet`) | core | resource lifecycle, scene tree, render dirty flags |

flecs's scheduling, pipeline, system framework, timing: **gone from the binary.** Saves ~50KB, removes ~30 public symbols we'd otherwise have to discipline ourselves not to call.

### 8.4 Pool unification (no bridge, no global state)

There is no bridge. There is no `ecs_os_api` modification. The scheduler dispatches directly to enki:

```c
for (size_t i = 0; i < wave->system_count; i++) {
    ke_task_scheduler_task_t t = {
        .fn   = run_system_trampoline,
        .arg  = wave->systems[i],
    };
    enki_handles[i] = task_scheduler->add(task_scheduler, &t);
}
task_scheduler->wait_for_all(task_scheduler, enki_handles, wave->system_count);
```

flecs (without pipeline) never creates a thread. enki is the only source of parallelism in the engine. Adding a second runtime instance in the same process is just creating a second `ke_runtime*` with its own `ke_ecs*` — no conflict, no shared state, no caveat.

### 8.5 Bevy-style C# ergonomics — the codegen path

What Bevy gives Rust devs via type inference (`Query<&mut T, &U>` → write T, read U), C# devs get via a Roslyn source generator that parses `Query<Mut<T>, Read<U>>` parameters and emits the `access_list` at compile time. The C ABI keeps the explicit `access_list` because dynamic bindings (Lua, Python) can't infer.

Three paths to `access_list` in C#, in increasing ergonomics:

1. **Manual declaration at register** — `RegisterSystem(new SystemParams { Reads = [...], Writes = [...], Execute = ... })`. Verbose. Identical to flecs C verbosity. Works without any codegen.
2. **Reflection at register** — inspect lambda/method generic parameters via `MethodInfo`. Tens of milliseconds at startup; zero runtime cost. Works without codegen.
3. **Source generator** (recommended once usage scales) — `[System(Phase.Update)] static void Foo(Query<Mut<T>>, Res<U>, ...) { ... }`. Codegen reads the parameter types, emits the descriptor + analyzer warnings on conflict. Same ergonomics Bevy users have.

Path 1 unblocks development immediately. Path 3 lands when system count makes manual lists painful. Codegen is **ergonomic enhancement, not a prerequisite** — the scheduler runs on whatever `access_list` it receives, regardless of how it was produced.

### 8.6 What runs where (the actual threading story)

```
ke.sim thread (drives the runtime tick loop)
│
├── runtime.tick(dt)
│    │
│    ├── for each phase in [PreUpdate, FixedUpdate×N, Update, PostUpdate, Extract]:
│    │    │
│    │    ├── waves = compute_waves(systems_in_phase)
│    │    │
│    │    └── for each wave:
│    │         ├── enki.add_task(system) for each system in wave   ◄── parallel here
│    │         ├── enki.wait_for_wave()
│    │         └── ecs.apply_deferred(wave.defer_queue)
│    │
│    └── frame packet ready
│
└── (between ticks: asset loaders, audio mixing, PSO compile etc.
     also dispatch directly to ke_task_scheduler — same enki pool)

ke.render thread
└── consumes frame packet, drives the renderer
```

One pool, used by everything. flecs (storage-only) never sees a thread. The scheduler is small, transparent, ours.

### 8.7 References worth pillaging

- **Bevy ECS source** — `bevy_ecs/src/schedule/` modules: `executor/multi_threaded.rs` for the wave dispatcher; `graph.rs` for the dep graph; `condition.rs` for run conditions. Algorithmic shape directly transferable to our C scheduler.
- **flecs 4 docs** — `ecs_query_*`, `ecs_iter_*`, `ecs_emit` (for triggering observers manually if we ever need to). Storage-side reading.
- **Glenn Fiedler — "Fix Your Timestep"** — canonical reference for the FixedUpdate accumulator in §8.2's `timestep.c`.
- **Sebastian Aaltonen's job system writeups** — background reading on cache-aware task partitioning; informs how we shape `wave_builder.c`'s system ordering.

---

## 9. Resource concept — separate from components

Bevy treats `Resource` as a distinct kind. flecs uses singleton entities. We mirror Bevy's distinction explicitly because:

1. Game devs reading code want to know "is this per-entity or global?"
2. Scheduler read/write set semantics are simpler with two slot types than with "singleton entity" sugar
3. Some impls don't have a singleton entity concept — `ke_resource_handle` works against any storage

`ke_resource_handle` is opaque; the runtime impl decides how to back it (flecs → singleton entity; custom → direct pointer slot).

Standard runtime-provided resources:
- `Time { float dt; uint64_t frame_index; float elapsed; }`
- `Input` (replaces the current `IInputReader` exchange)
- `WindowSize { int width, height; }`
- `FramePacket *` (the sim→render handoff buffer)

Modules add their own (`Box2DWorld`, `AudioMixer`, etc.).

---

## 10. Migration plan (parallel, not big-bang)

The current `ke_ecs` sparse-set + `Application.cs` orchestration stays alive through the entire migration. **`ke_runtime` is additive**.

### Phase R0 — Contract lock-in (this doc + iteration)
Write the contract above as actual C headers. No impl yet. Review with user. Lock when both sides happy.

### Phase R1 — flecs spike ✅ (commit `b58b21f`)
Stood up `src/c/runtime/flecs/` (early layout — to be reorganized in R2.5) with `ke_runtime_flecs_create()` wrapping flecs's pipeline. 5 integration tests proved the vtable shape (register_module + register_system + tick + destroy). **Outcome**: vtable shape validated. The spike used flecs's pipeline; that approach was replaced after the §8.1 evaluation.

### Phase R2 — `KernelEngine.Runtime.Flecs` C# binding ✅ (commits `87001a0`, `e3fba2a`)
ClangSharp bindings + `FlecsRuntime` C# wrapper + 8 C# integration tests + `00_runtime_minimal` example (R3-A) opening a GLFW window driven by the runtime. **Outcome**: ABI crosses to managed cleanly; trampoline pattern works; host-driven frame loop with runtime tick works end-to-end.

### Phase R2.5a — flecs 4.1.5 upgrade ✅ (commit `df48365`)
Bumped vcpkg to flecs 4.1.5 via `overrides`. Single API break adapted (`ecs_entity_desc_t::add` array→pointer). All R1/R2 tests stayed green. Upgrade is sunk cost we paid before the storage/scheduler split decision, but it's reusable: 4.x is where we want to live anyway.

### Phase R2.5b — Split plugins: runtime vs ECS

Reorganize the C source layout to match the new doctrine:

- **Move**: `src/c/runtime/flecs/` storage helpers → `src/c/ecs/flecs/`
- **Create**: `src/c/runtime/` for our own pure-C scheduler (no flecs dep)
- **Rebuild**: flecs as a CMake target with `FLECS_PIPELINE`, `FLECS_SYSTEM`, `FLECS_TIMER` `#define`s **removed**. Compile-time strip of the scheduler addons.
- **Rewrite headers**:
  - `kernel_engine/kernel/runtime/runtime.h` — runtime vtable + factory (`ke_runtime_create`)
  - `kernel_engine/kernel/ecs/ecs.h` — expanded `ke_ecs` contract (multi-component query, With/Without filters, observers, hierarchies)
  - `kernel_engine/kernel/ecs/flecs/ecs_flecs_create.h` — `ke_ecs_flecs_create()`
- **C# side**: `KernelEngine.Runtime` + `KernelEngine.Ecs.Flecs` as separate projects. DI registers them independently. The R3-A example wires both.

### Phase R2.5c — Scheduler core in pure C

Implement `src/c/runtime/src/scheduler/`:
- `system_ctx.c` — `ke_system_ctx` impl per §15.8 (stack-allocated, debug-checked access door) (~120 LoC)
- `wave_builder.c` — R/W conflict grouping (~150 LoC)
- `dispatcher.c` — enki dispatch + wave barrier + defer flush; builds `ke_system_ctx` per callback (~120 LoC)
- `phase_loop.c` — phase orchestration + fixed-timestep accumulator (~180 LoC)
- `defer_queue.c` — per-wave command queue applied through `ke_ecs*` (~150 LoC)
- `timestep.c` — Glenn Fiedler accumulator (~50 LoC)
- **Migrate the execute signature** `(ke_runtime*, void*, float)` → `(ke_system_ctx*, void*, float)` across runtime headers + C# binding + existing tests/example

Tests:
- Wave builder: synthetic system sets with known conflict patterns → expected wave layout
- Dispatcher: N systems in parallel run in N≤workers threads (measured via thread-id set)
- Defer queue: spawn+add+remove ordering preserved at barrier flush
- Fixed-timestep: accumulator catch-up, no drift over 60s

Estimated: 4-5 sessions for R2.5b + R2.5c combined.

### Phase R3 — First real consumer: a minimal example (NOT Pong yet)
Port `01_window_scene` to use the runtime. Window module, render module (still wrapping old `KernelEngine.Render.Bgfx`), one example-specific module. Old `Application.cs` is bypassed entirely for this example. **Both worlds coexist**: `01_window_scene` uses runtime; other examples still use Application.cs.

### Phase R4 — Render module wrap of existing renderer
Wrap the current `KernelEngine.Render.Bgfx` in `RenderModule` (Module = registers MeshRenderSystem, ShadowRenderSystem, etc., as Extract-phase systems). No render rewrite — just orchestration shim. Now any example can opt into runtime by adopting RenderModule.

### Phase R5 — Pong migration
Pong becomes its own module. `PaddleSystem`, `BallSystem`, `ScoreSystem` registered via Module.OnLoad. Original Pong's `Paddle.cs : Node` subclass pattern is preserved at the **node** level (Tree/Node ergonomics survive); the **system** level uses the new ABI underneath. Validates end-to-end.

### Phase R6 — Migrate examples 02-15 one by one
Mechanical port. Old `Application.cs` stays for any example that hasn't been touched.

### Phase R7 — Delete `Application.cs`
After all examples + games migrated. Old sparse-set ECS impl stays as alternative (could be re-promoted to its own `ke_runtime` impl if anyone wants it back; or just deleted).

### Migration risk gates
- After R1: ABI shape is sound. ✅
- After R2.5a: flecs 4.1.5 builds + tests stay green. ✅
- After R2.5b: plugins split cleanly; runtime depends only on `ke_ecs*` + `ke_task_scheduler*` (no flecs symbol leakage); flecs compiled without pipeline addons; build smaller.
- After R2.5c: scheduler runs parallel waves on enki; defer queue applies correctly; fixed timestep doesn't drift; all unit tests + R1/R2 integration tests green. **Hard gate before R3.**
- After R3: contract proves it can host a real frame with renderer + window. If shape is wrong, revise the doc and try again before going deeper.
- After R5: Pong runs end-to-end identical visually + behaviorally. Hard gate.

---

## 11. Open questions

1. **Module versioning** — should `ke_module_params` carry a version field for ABI evolution? V2 says yes; defer the actual checking to V3 hot-reload era.
2. **Resource ownership** — who owns the bytes behind `ke_resource_handle`? Runtime, or allocator passed in? Probably runtime, with allocator hint. Lock in during R1.
3. **Cross-runtime portability of modules** — if a Module is written against the ABI, does it work on any `ke_runtime` impl + any `ke_ecs` impl? Yes by design: modules only see the contract surface. **But**: modules using `ke_ecs_flecs`-specific features (observers, prefabs, relationships, rich query terms) won't run on sparse-set. **Doctrine**: modules that need those features explicitly require a richer `ke_ecs` impl in their dependency list (analogous to how a render module today requires `ke_render`); they don't pretend to be portable.
4. **Render world separation** — currently the doc says render is NOT a separate runtime (it's a pipeline consuming the snapshot). Bevy uses a separate "sub-app" world. Lock the simpler "pipeline-only" approach unless a real use case demands sub-app.
5. **`ke_ecs` surface expansion** — multi-component queries (`query<T1, T2>`), entity generations (stale-ID detection), filters (`With`/`Without`), observers (`OnAdd`/`OnRemove`/`OnSet`), hierarchies (parent/child queries). Lands in the `ke_ecs` contract during R2.5b so every impl exposes the same surface. `KernelEngine.Ecs.Flecs` forwards to flecs's native primitives; the hand-rolled sparse-set impl in `src/c/kernel/` either grows to match or accepts a "low-tier alternative" label (some calls return `KE_ERROR_NOT_SUPPORTED`).
6. **Lua/scripting integration** — how does a Lua script declare a Module? Probably a builtin `LuaScriptModule` that the runtime registers; Lua scripts then register systems through that bridge. Deferred to post-R5.
7. **Variadic queries in the C# source generator** — `Query<T1, T2, T3, T4, ...>` is unbounded in arity. Approaches: (a) generate `Query<T1>` through `Query<T16>` overloads (closest to how Bevy 0.x handled it before const generics); (b) use C# `ITuple` + boxing (slow); (c) emit per-method-call specialized query types in the generator (most flexible, more codegen). Lock during R2 once the source generator stub exists.

---

## 12. Non-goals (explicit)

- **Hot module reload** — V3 concern. Modules load once at startup.
- **Distributed / networked runtime** — out of scope.
- **Runtime swappable mid-game** — pick `SimpleRuntime` (or future alternatives) at startup, stays for the session.
- **Replacing `ke_ecs` storage mid-game** — the runtime receives an `ke_ecs*` at construction; the choice is locked for the session. (You can pick which ECS impl when constructing the runtime — sparse-set today, future `ke_ecs_flecs` tomorrow — but not swap mid-game.)

---

## 13. Alternatives considered

**Scheduling integration with flecs** (the central question — full evaluation in §8.1):

- **(A) flecs pipeline + `ecs_os_api` bridge to enki**. Override `task_new_/task_join_` globally so flecs's parallel dispatch routes through enki. **Rejected**: `ecs_os_api` is process-global; introduces "1 flecs runtime per process" constraint and a permanent thread-shaped/task-shaped impedance mismatch. The flecs dialect contaminates the runtime corner of the engine forever.
- **(B) flecs single-threaded; enki explicitly for everything else**. **Rejected**: surrenders ECS parallelism by choice. The wave model we want is achievable without surrendering anything.
- **(C) Two pools (flecs threads + enki workers, OS arbitrates)**. **Rejected**: oversubscription.
- **(D) Our scheduler, flecs storage-only**. **Chosen.** Buys external harmony (engine reads as one engine) at the cost of writing the wave dispatcher ourselves. flecs `FLECS_PIPELINE` addon disabled, scheduler code physically not compiled.

**ECS storage choice** (evaluated after the scheduler decision narrowed scope to "storage only"):

- **EnTT** (C++17, header-only, MIT, AAA-track-record — Minecraft, O3DE). Storage-only by design (best architectural fit). Rejected for now: C++ template-heavy → per-component wrap shim required for our C ABI surface (~real friction every time a component is added); no native parent/child hierarchies (scene tree would be rebuilt on top); no pairs/relationships (closes a door we want open). **Credible fallback if flecs ever bites us.**
- **gaia-ecs** (C++20, header-only, MIT, modern challenger). Same C ABI friction as EnTT, plus smaller community + bus-factor 1. **Reassess in ~2 years** when track record builds.
- **Hand-rolled sparse-set ECS** (the one already in `src/c/kernel/`). Lacks hierarchies, observers, queries beyond single-component. Stays alive only as a low-tier alternative impl of `ke_ecs` for those who want zero-dep storage.

**Other rejected paths**:

- **Forcing flecs to satisfy `ke_task_scheduler` too** — flecs's pool is designed for ECS dispatch, not generic compute. Adapter would need dummy worlds per dispatch. enkiTS stays as `ke_task_scheduler`.
- **Bevy ECS as a direct copy** — Rust, doesn't transfer. The algorithmic shape (declared access + waves + deferred + fixed timestep + source-gen ergonomics) is what we copy; the code stays in Rust.
- **Don't have a runtime; keep `Application.cs`** — that's the current state. The doc exists because that state has failed the simplicity test for a >1-binding engine.
- **External job library besides enkiTS** (Intel TBB, Marl, NVIDIA Hwloc) — enkiTS is already in the engine, already wrapped, already mature. No reason to swap.

---

## 14. Status & next actions

- [x] User reviews this doc
- [x] Lock the C ABI vtable shape + Module/System lifecycle + Phase enum (§3)
- [x] R1: flecs build spike (commit `b58b21f`) — validated ABI shape, surfaced flecs storage/scheduler coupling
- [x] R2: C# bindings via ClangSharp + `FlecsRuntime` wrapper + 8 managed tests (commits `87001a0`, `e3fba2a`)
- [x] R2 extra: `00_runtime_minimal` example proving GLFW window + tick loop run end-to-end (commit `e3fba2a`)
- [x] Companion doc: [`RenderArchitectureV2.md`](RenderArchitectureV2.md)
- [x] §3.4 factory signature documented — runtime accepts injected `ke_ecs*`; storage plugin (`KernelEngine.Ecs.Flecs`) is a separate factory
- [x] §8 settled — Opção D (our scheduler, flecs storage-only with `FLECS_PIPELINE` off); evaluation of A/B/C/D recorded
- [x] §13 alternatives revised — A/B/C rejected with explicit reasons; EnTT/gaia-ecs evaluated and parked as fallback
- [x] §15 game script safety model locked — `ref struct View` (C#) + `ke_system_ctx` (universal C ABI) + 3-layer AOT enforcement; native/dynamic-language paths covered via debug-checked door; `ke_script_component` reshape spec'd; §15.10 Node fields are components (auto `<ClassName>_Data` via codegen; `[Local]` opt-out disables parallelism; non-POD without `[Local]` fails build)
- [x] R2.5a — flecs 4.1.5 upgrade + revert to baseline 3.2.11 (override removed; Option D didn't need flecs 4-specific APIs)
- [x] **R2.5b — Plugin split** done in 3 stages on branch `feat/runtime-v2`:
   - Stage A `2ecc052` — create `src/c/ecs/flecs/` + `src/c/runtime/` plugins, legacy spike still present
   - Stage B `0119ff5` + `d3be264` — `KernelEngine.Ecs.Flecs` + `KernelEngine.Runtime` C# projects (hand-rolled P/Invoke pending ClangSharp regen)
   - Stage C `5058646` — delete legacy `src/c/runtime/flecs/` + old C# projects
   - Header split `685985c` — `ke_ecs_flecs_create` moved to its own header so ClangSharp targets `libraryPath=ke_ecs_flecs` without leaking into Kernel.Native
- [x] **R2.5c — Scheduler core** delivered as 5 focused commits:
   - `9e30261` fixed-timestep accumulator (Glenn Fiedler) + spiral-of-death guard
   - `3302e24` R/W metadata in `ke_runtime_system_params` (`access_list`/`exclusive`) + debug-mode `ke_system_ctx` access checks (log-and-counter mode; R2.5c-final flips to `abort()`)
   - `a2ceff1` wave builder (Bevy-style greedy R/W conflict grouping) + 8 unit tests
   - `309f4b1` defer queue functional — spawn/attach/detach/despawn enqueue + flush at wave barrier
   - `4ca2ea8` enki dispatcher real — `ke_task_scheduler*` injected in factory; per-task ke_system_ctx + local defer queue; parallel within wave + barrier sync
   - 29/29 C++ tests green (18 RuntimeSpike + 8 WaveBuilder + 3 defer queue), 9/9 C# tests green, `00_runtime_minimal` example wires enki + flecs + runtime
- [x] **R2.5d — Polish closed** (Kanban A14):
   - [x] **ClangSharp regen (commit `820f316`)** — `Runtime.rsp` + `EcsFlecs.rsp` under each project's `Native/`; hand-rolled `NativeMethods.cs` deleted; manual patch on `ke_runtime_system_params.cs` gone (Kernel.rsp regen picks up new fields cleanly); `GlobalUsings.cs` per project pulls in `KernelEngine.Kernel.Native`; exception slot moved from `[ThreadStatic]` to lock+static (enki trampoline runs on worker threads).
   - [x] **Strip flecs addons — dropped 2026-06-10**. Staying on vcpkg-supplied `flecs_static.lib`. Doctrine ("flecs is storage only") is enforced by our code not calling pipeline/system/timer symbols; physical strip is binary-size optimization, not behavior change. Linker DCE removes most unused code at link time. Re-open if binary size becomes a real concern.
- [ ] **R3 — First real example consumer (`01_window_scene` ported to runtime)**
- [ ] **R4 — Render module shim wrapping the current `KernelEngine.Render.Bgfx`** (so any example can opt into runtime keeping the current renderer)
- [ ] **R5 — Pong migrated to runtime** (hard gate: identical visual + behavioral)
- [ ] **R6 — Examples 02-15 migrated incrementally**
- [ ] **R7 — `Application.cs` deletion** (after every consumer migrated)

**This doc is the contract.** §3 vtable + Module/System/Phase shape are locked; §8 doctrine pivoted to Opção D after the harmonia/singleton evaluation and is now the current contract. §15 game script safety model is locked at design level; impl evolves manually-first → codegen-second per §15.6. Impl drift away from any locked section is a bug in the impl, not in the doc.

---

## 15. Game script safety model — NodeBehavior + ref struct View + analyzer-enforced funnel

The script layer (Node subclasses + NodeBehaviors written by game devs) is **the** consumer of the runtime's parallel scheduling. For the scheduler to auto-parallelize scripts safely, the static analyzer must be able to determine the exact R/W set of every script callback. That guarantee is only complete if reflection, unsafe pointer munging, and runtime-typed component access are physically banned in script code. This section locks the doctrine.

### 15.1 The funnel — `ref struct View`

All component / resource access in script code goes through a **`ref struct View`** passed as a parameter to script callbacks. Because `ref struct` cannot:
- Be a field of any class or struct
- Be captured by a lambda or local function
- Cross an `await` or `yield` boundary
- Be boxed (assigned to `object`)
- Escape the stack frame in any form

…the C# compiler **physically enforces** that the access handle never reaches code the analyzer hasn't seen. No discipline required — the build fails.

```csharp
public class Paddle : Node {
    public override void OnUpdate(float dt, View view) {
        view.Velocity.X = view.Input.GetAxis("Move") * 5f;
        view.Transform.Position.Y += view.Velocity.Y * dt;
    }
}
```

The View is generated per-class by the codegen (§15.6) — exposes only the components/resources declared by the class via `[ComponentAccess<T>]` attributes (or inferred by the analyzer).

### 15.2 Banned APIs in script code

The analyzer rejects (severity per §15.5):
- `System.Reflection.*` (including `Type.GetField`, `GetCustomAttribute`, etc.)
- `unsafe` keyword
- `[DllImport]` / P/Invoke
- `dynamic` keyword
- Dynamic-ID overloads of ECS API (only generic methods like `GetComponent<T>()` allowed; never `GetComponent(typeId)`)
- Open-generic recursive patterns the analyzer can't monomorphize

These are not enforced on engine/framework code — only on assemblies marked as script code (e.g. via `[assembly: KernelEngineScriptAssembly]`).

### 15.3 The `NodeBehavior` pattern — replacing capability methods

Earlier drafts proposed framework-provided "capability methods" (`view.MoveOverTime`, `view.FlashColor`, etc.). Rejected — ad-infinitum framework responsibility, ticket-treadmill maintenance.

**The doctrine**: the framework ships ONE syntactic surface for "behavior with state that ticks over time" — `NodeBehavior`. Codegen transforms it into component + system invisibly. Devs write game-specific behaviors infinitely without ever typing `[Component]` or `[System]`.

```csharp
public partial class JumpEffect : NodeBehavior {
    public float TimeLeft;
    public Vector3 Velocity;
    
    public void Run(View view, float dt) {
        TimeLeft -= dt;
        view.Transform.Position += Velocity * dt;
        if (TimeLeft <= 0) Finish();
    }
}

// Usage in any Node:
view.Attach(new JumpEffect { TimeLeft = 0.3f, Velocity = new(0, 5, 0) });
```

Codegen emits:
- A POD component (`JumpEffect_Data`) holding the public fields
- A system (`JumpEffect_Tick`) querying all entities with that component and invoking `Run`
- `View.Attach<JumpEffect>(...)` / `View.Detach<JumpEffect>()` extensions
- The R/W metadata for the system, inferred from `Run`'s body via §15.4

Framework ships: `NodeBehavior` base class (~30 LoC) + the codegen + 3 canonical examples (`Timer`, `Tween`, `Delay`) in the Reference docs. Community/games extend the pattern endlessly — framework code doesn't grow.

### 15.4 R/W inference from script bodies

The analyzer scans the body of every `OnUpdate(float, View)` and every `NodeBehavior.Run(View, float)`. For each method, it identifies every component/resource access through the View parameter and aggregates into reads/writes sets.

Inferable confidently (all cases):
- `view.GetComponent<T>()` / `view.GetMut<T>()` → read/write T
- `view.Query<T>()` / `view.QueryMut<T>()` → read/write T (across entities)
- Generated property accesses on the View → component access (View is a typed surface)
- Resource access via `view.Resource<T>()` → read T resource
- Branches and loops: union of all reachable branches (conservative but correct)
- Calls into other analyzed methods: trace into callee, union into caller's set
- Monomorphized generic calls: specialize per call site

Fall back to **exclusive system** (no parallelism) when the analyzer can't prove safety:
- Open-generic call sites with no concrete instantiation in scope
- (No other cases — §15.2 bans the remaining holes)

The analyzer never produces a false-positive parallel marking. The funnel guarantees that what the analyzer doesn't see cannot exist.

### 15.5 Severity-adjustable enforcement — Roslyn analyzer that reads MSBuild

The analyzer reads the consuming project's `<PublishAot>` MSBuild property via `AnalyzerConfigOptionsProvider.GlobalOptions.TryGetValue("build_property.PublishAot", ...)` at compilation start. Severity flips:

- **`PublishAot != "true"` (debug-mode JIT)**: violations of §15.2 emit **warning** (yellow squiggle in IDE). Build passes. Dev iterating gets immediate feedback without the AOT slowdown.
- **`PublishAot == "true"` (release-mode AOT)**: same violations emit **error** (red squiggle). Build fails.

Escape hatch (debug-only): `<KernelEngineAllowJit>true</KernelEngineAllowJit>` in csproj suppresses the JIT warnings entirely for devs who know what they're doing. Not available in release configuration.

### 15.6 Implementation order — manual first, codegen later

The doctrine is locked at design level; the impl ships in two phases to validate the concept end-to-end before paying the codegen cost.

**Phase 1 — manual surface (validates the runtime + ECS path)**:

- `NodeBehavior` base class exists
- Devs write per-behavior **`partial`** class that declares the `_Data` component, the `_Tick` system, and the `View` extension methods by hand
- Mechanical boilerplate (~30-50 LoC per behavior) but exercises every layer of the funnel and proves the parallelization works
- One or two examples in the test suite exercise this manually

**Phase 2 — codegen (eliminates the boilerplate)**:

- Roslyn source generator + analyzer ship
- The manual classes from Phase 1 get their boilerplate deleted; codegen takes over
- Analyzer severity-flipping per §15.5 enabled
- Tests already exist (from Phase 1) — codegen output must match manual hand-rolled output

Phase 2 is **a single multi-session focused effort** (estimated 6-10 sessions for production-quality codegen + analyzer). Worth doing once the runtime + ECS + script funnel are proven to actually parallelize correctly on real workloads.

### 15.7 AOT enforcement at build time (defense in depth)

Beyond the analyzer (§15.5), the framework also ships an MSBuild `.targets` file that fails the build in release configuration without AOT — defense against analyzer-bypass attempts:

```xml
<Target Name="_KernelEngineEnforceAot" BeforeTargets="Build"
        Condition="'$(Configuration)' == 'Release'">
  <Error Condition="'$(PublishAot)' != 'true' AND '$(KernelEngineAllowJit)' != 'true'"
         Text="KernelEngine release builds require &lt;PublishAot&gt;true&lt;/PublishAot&gt;..." />
</Target>
```

Plus a runtime sanity check at engine init that throws `EngineConfigurationException` if `RuntimeFeature.IsDynamicCodeSupported` is true in release config — catches escapes from someone who bypassed both the analyzer and the MSBuild target.

Three layers: analyzer (IDE-time), MSBuild (build-time), runtime (startup). Each layer is independent; bypassing all three would require active malice.

### 15.8 Native + dynamic-language safety — `ke_system_ctx` at the C ABI

§15.1-15.7 cover the C# script layer. The same physical safety must hold for every other consumer of `ke_runtime`: native plugins (C/C++), Lua scripts, Python bindings, future Rust bindings, and the legacy `ke_script_component` callback path. The mechanism is the same — **a single API doorway to component memory, checked at the doorway** — only the per-language sugar above it differs.

The doorway is `ke_system_ctx*`. Inside a system callback, `ke_system_ctx*` is the **only** way to read or mutate component state. Every other handle to `ke_ecs*` is opaque to the system body.

```c
typedef struct ke_system_ctx ke_system_ctx;  // opaque

// Read access — debug build asserts cid is in ctx's declared reads (or writes).
const void *ke_system_ctx_get(ke_system_ctx *ctx, ke_component_id cid, ke_entity_t e);

// Write access — debug build asserts cid is in ctx's declared writes.
void *ke_system_ctx_get_mut(ke_system_ctx *ctx, ke_component_id cid, ke_entity_t e);

// Query — same access checks, applied to every cid in the list.
ke_query_iter ke_system_ctx_query(ke_system_ctx *ctx,
                                  const ke_component_id *cids,
                                  uint32_t                count);

// Deferred mutations — enqueued, applied at the next wave barrier.
ke_entity_t ke_system_ctx_spawn  (ke_system_ctx *ctx);
void        ke_system_ctx_attach (ke_system_ctx *ctx, ke_entity_t e, ke_component_id cid, const void *data);
void        ke_system_ctx_detach (ke_system_ctx *ctx, ke_entity_t e, ke_component_id cid);
void        ke_system_ctx_despawn(ke_system_ctx *ctx, ke_entity_t e);

// Resources — same access checks against declared resource set.
void *ke_system_ctx_resource(ke_system_ctx *ctx, ke_resource_handle h);
```

**System callback signature** (replaces the earlier `(ke_runtime*, void*, float)` shape from the R1 spike):

```c
typedef void (*ke_system_execute_fn)(ke_system_ctx *ctx, void *user_data, float dt);
```

The ctx is **stack-allocated by the scheduler** before invoking the callback, lives only for the duration of that one call, and is destroyed when the callback returns. Storing the ctx pointer in a global / field / closure is undefined behavior — in debug builds the scheduler tags ctx instances with a sentinel and asserts a fresh sentinel on every API call, catching stale-pointer use.

**Debug check** (zero overhead in release):

```c
void *ke_system_ctx_get_mut(ke_system_ctx *ctx, ke_component_id cid, ke_entity_t e) {
#ifndef NDEBUG
    if (!access_list_contains_write(ctx->writes, ctx->write_count, cid)) {
        ke_logger_error(ctx->logger,
            "system '%s' accessed component %u as MUT but did not declare write access. "
            "Add { .cid = %u, .access = KE_ACCESS_WRITE } to ke_system_params.access_list.",
            ctx->system_name, cid, cid);
        ke_debug_break();
    }
#endif
    return ke_ecs_get_mut(ctx->ecs, e, cid);
}
```

In release, the check is elided by the preprocessor; the function inlines to a direct `ke_ecs_get_mut` call. **Zero runtime cost in shipping binaries.**

#### Per-language enforcement matrix

| Caller | Compile-time guarantee | Runtime check (debug) |
|---|---|---|
| **C# game script** (Node, NodeBehavior) | full — `ref struct View` + analyzer (§15.1, §15.5) | redundant but harmless |
| **C# engine code** (Framework internals) | none | check fires |
| **Native plugin** (engine dev writing C/C++) | none — engine devs are trusted | check fires |
| **Lua / Python / dynamic binding** | none | check fires |
| **Native script** (`ke_script_component`) | none | check fires (§15.9) |

The safety lives in the API, not in the language. Languages with more expressive type systems (C# `ref struct`) add **compile-time enforcement** on top — bonus, not prerequisite. Languages without (C, Lua, Python) get **runtime enforcement in debug** — sufficient because the API is the only door, and the door checks.

### 15.9 `ke_script_component` reshape

Today's `ke_script_component` carries function-pointer callbacks that receive only `ke_entity_t` and have no path to component state except via globals (`ke_ecs* g_ecs;`) or implementation-private wrappers — the C# Node bridge currently does the latter. This is the same hole §15.1 closes for C#, replayed at the C kernel level.

**New shape**:

```c
typedef struct ke_script_component {
    bool started;

    void (*on_start)(ke_system_ctx *ctx, ke_entity_t entity);
    void (*on_update)(ke_system_ctx *ctx, ke_entity_t entity, float dt);

    // Declared access — read by the scheduler when building the ctx for this system.
    const ke_component_access *access_list;
    uint32_t                   access_count;
    const ke_resource_handle  *resource_reads;
    uint32_t                   resource_read_count;
    const ke_resource_handle  *resource_writes;
    uint32_t                   resource_write_count;
} ke_script_component;
```

The internal `ScriptSystem` (engine-provided, walks all entities with `ke_script_component` each tick) builds one ctx per script callback before invocation. The ctx inherits the script's declared `access_list`, so the same debug-time checks apply uniformly to scripted entities.

**Default for scripts that don't declare access**: `exclusive = true` flag on the script component. Scheduler treats the ScriptSystem as a single wave entry that conflicts with everything — runs alone, safe by default. Devs (or codegen) populate the access lists when they want their scripts to parallelize with engine systems.

**C# `View` layered over native ctx**: the `ref struct View` is the C# wrapper around `ke_system_ctx*`. Every `view.Transform.Position = ...` lowers to `ke_system_ctx_get_mut(ctx, CID_TRANSFORM, this.Entity)->Position = ...` underneath. The ref struct adds compile-time enforcement; the underlying call still goes through the debug-checked door.

### 15.10 Node fields are components (everything is component, by default)

The doctrine "all game state lives in the ECS" extends to Node and NodeBehavior subclass fields. **Every declared field on a Node/NodeBehavior subclass becomes part of an auto-generated `<ClassName>_Data` component**; the codegen rewrites field accesses to route through the View. The dev's experience is Unity-like (declare fields, use them as fields); the runtime sees ECS data.

```csharp
public partial class Paddle : Node {
    public float Speed = 5f;
    public Color Color = Color.Red;
    private int  _score = 0;

    public override void OnUpdate(float dt, View view) {
        view.Transform.Position.X += Speed * dt;
        view.Material.Tint = Color;
        if (BallCrossedGoal()) _score++;
    }
}
```

Codegen emits the equivalent of:

```csharp
internal struct Paddle_Data {
    public float Speed;
    public Color Color;
    public int   _score;
}

// Spawn helper attaches the component on entity creation
public static Paddle Spawn(Scene scene, /* init */) {
    var e = scene.Spawn();
    scene.Attach(e, new Paddle_Data { Speed = 5f, Color = Color.Red, _score = 0 });
    return Paddle.For(e);
}

// Field accessors route to the component
public partial class Paddle {
    public ref float Speed  => ref _view.Get<Paddle_Data>().Speed;
    public ref Color Color  => ref _view.Get<Paddle_Data>().Color;
    public ref int   _score => ref _view.Get<Paddle_Data>()._score;
}
```

**Performance note**: codegen takes the ref to `<ClassName>_Data` **once per OnUpdate invocation** and reuses via local ref — one ECS lookup per frame per node, not one per field access. Comparable cost to Unity's `transform.position` indirection.

#### Consequences ride for free

| Concern | How it works |
|---|---|
| **Serialization (save / load)** | Components serialize uniformly; saving the game = serializing the world; loading = deserializing into a fresh world; Node instances re-created as wrappers when needed. Zero per-class serialization code. |
| **Hot reload** | State lives in ECS, not in the C# instance heap. Recompile, rebind class metadata, data continues where it was. |
| **Networking** | Replicating `Paddle_Data` over the wire replicates Paddles. State-is-component is the same primitive Bevy networking uses. |
| **Determinism** | No hidden heap state → same `Paddle_Data` + same input = same output. Replay viable. |
| **Editor inspection** | Editor reads/writes `Paddle_Data` directly via the ECS API. No reflection over Node instances needed. |

#### Edge case — fields that *can't* be components

Some state genuinely doesn't fit in a POD component:
```csharp
private List<EnemyTarget> _nearbyEnemies;     // heap, recomputed each frame
private TaskCompletionSource _asyncWaiter;    // async coordination
private MemoryStream _ioBuffer;               // transient IO
```

For these, the codegen requires explicit opt-out:

```csharp
[Local] private List<EnemyTarget> _nearbyEnemies;
```

`[Local]` fields are stored **on the C# Node instance heap**, not in the ECS. Consequences:
- They don't serialize (save/load skips them).
- They don't replicate (networking ignores them).
- They **disqualify the Node's `OnUpdate` from parallel scheduling** — analyzer marks the system as `exclusive = true` if any code path reads or writes `[Local]` state, because a heap field could be touched from multiple threads if the Node ever existed on multiple entities or in any extension context.

The dev makes the trade consciously: heap state ↔ no parallelization, vs component state ↔ free parallelization.

#### Codegen safety rule

A non-`[Local]` field with a non-POD type (anything containing references — `List<T>`, `string` longer than inlined, `Task`, delegate types) **fails the build**:

> `error KE0042: 'Paddle.Spawn' field type 'List<EnemyTarget>' is not POD; cannot live in a generated _Data component. Either move the data to value-type form, or mark the field with [Local] to keep it on the instance heap (disables parallel scheduling).`

Forces the dev to declare intent. Silent acceptance of non-POD state into a component would break serialization or replication invisibly; the build refusal makes the cost explicit upfront.

#### NodeBehavior follows the same rule

The `NodeBehavior` pattern (§15.3) already treats its fields as a component (`<Behavior>_Data`). §15.10 generalizes that doctrine to **all** Node subclasses, not just NodeBehaviors. The mental model is unified: **every class that descends from Node IS a component-bearing entity**, codegen-mediated. Whether you call it a "Node subclass" (long-lived entity, has lifetime, has OnUpdate) or a "NodeBehavior" (attached/detached effect, has its own data) is a naming convenience — under the hood, both are codegen-generated component + system pairs.

---

## 16. Future doctrine: component snapshot for sim/render pipelining

Locked at design level 2026-06-10; impl deferred to R6-R7 (post Pong migration, when frame budget shows the need). This section records WHY we picked the shape, so future implementation doesn't re-litigate.

### 16.1 The problem

R4 (in progress) delivers unified scheduling: render passes are systems, scheduler dispatches via pinned worker, single world, zero locks in app code. But sim and render alternate within a tick — no pipelining. On heavy scenes capped at vsync, this leaves ~15-30% of CPU budget unused vs an engine that runs sim N+1 in parallel with render N.

Pipelining requires SOME form of state separation: sim N+1 cannot mutate what render N is reading. The question is what shape that separation takes.

### 16.2 Options evaluated

| | A) Separate worlds (Bevy) | B) Component snapshot | C) Frame packet | D) Deferred writes |
|---|---|---|---|---|
| State separation | full Render World | per-component back buffer | dedicated buffer | scheduler-tracked deferral |
| Single world | ❌ | ✅ | ✅ | ✅ |
| Render-as-system | ✅ | ✅ | ❌ (packet consumers) | ✅ |
| Unified R/W metadata | partial | ✅ | ❌ | ✅ |
| Memory cost | full render-relevant subset | per-component, sparse | fixed packet schema | deferred-writes buffer |
| Deadlock risk | low | low | low | high |
| Locks in app | zero | zero | zero | zero |
| Impl cost | extending ECS conceptually | extending ECS contract (`KE_COMPONENT_DOUBLE_BUFFERED`) | maintain packet schema | sophisticated scheduler tracking |
| Frame packet pattern (current) | replaces | replaces | preserves | replaces |

**Chosen: Option B with inference.**

### 16.3 The proposal — component snapshot via ke_ecs extension

Components flagged double-buffered get a back buffer in the storage layer. Phase boundaries (or explicit barriers) swap the buffers atomically. Render systems read snapshot; sim systems read/write live. No separate world; no explicit extract copy step.

```c
// ke_ecs contract addition (R6+):
typedef enum ke_component_flags {
    KE_COMPONENT_NONE             = 0,
    KE_COMPONENT_DOUBLE_BUFFERED  = 1 << 0,
} ke_component_flags;

ke_component_id (*component_register_v3)(struct ke_ecs *self,
                                          const char        *name,
                                          size_t             element_size,
                                          ke_component_flags flags);

// Atomic snapshot swap at phase boundary (called by scheduler):
void (*swap_snapshots)(struct ke_ecs *self);
```

The flecs impl behind this: each double-buffered component becomes two internal flecs components (`X_live` + `X_snap`). Swap rotates an index. Reads from render phase route to `X_snap`; reads from sim phases route to `X_live`. R/W metadata in `ke_runtime_system_params.access_list` becomes phase-aware: same `KE_ACCESS_READ` on Transform reads live in sim phases, snapshot in render phases.

### 16.4 Inference, not manual marking

Game devs must not be required to mark components. Inference:

```
at runtime startup:
    for each registered system with phase ∈ {EXTRACT, RENDER_*}:
        for each cid in system.access_list:
            mark cid as KE_COMPONENT_DOUBLE_BUFFERED

components never accessed by render-phase systems: stay single-buffered, zero overhead.
```

The marking is observable but automatic. Escape hatch: `[NoDoubleBuffer]` attribute on a component forces single-buffer even if a render system touches it (rare; degrades to sim/render sharing). Inversely, `[ForceDoubleBuffer]` forces double-buffer if the dev knows future render systems will need it. Both are escape hatches, not the rule.

### 16.5 Cost analysis

**Memory**: best case — only components accessed by render systems are duplicated, sparse. Worst case (all components accessed) — equals Bevy's Render World cost (subset of Main duplicated). Never worse than Bevy; usually less.

**Cache**: snapshot lives adjacent to live; when render reads, the snapshot likely shares cache lines with the sim writer's recent traffic from frame N-1. Frame packet would force a separate allocation.

**Impl**: 2-3 sessions of focused work on the `ke_ecs` contract + flecs wrapper. Inference (~1 session). Migrating existing render code to use phase-aware reads (~1 session). Total: 4-5 sessions when undertaken.

### 16.6 What R4 commits to today

R4 ships:
- Pinned worker for render-thread-affine systems
- Render passes as systems with R/W metadata
- Unified `wave_builder` algorithm across sim + render passes
- Single world, no snapshot, no pipelining

R4 explicitly does NOT block pipelining. The `ke_ecs` extension in R6+ slots in without R4 refactor: existing render systems start reading snapshot transparently once inference kicks in, sim systems continue writing live as before.

### 16.7 What we considered and rejected

- **Separate Render World (Bevy)** — rejected: violates single-world principle. State extraction step adds latency + complexity without per-component memory savings.
- **Frame packet (the pre-discussion design)** — rejected: breaks scheduler unification. Render passes become packet consumers with a different access language; render_graph stays as a parallel algorithm to wave_builder.
- **Deferred-write tracking** — rejected: deferred queue can balloon arbitrarily; deadlock risk if sim waits on resource render holds.

### 16.8 Where this is tracked

- Memory: `project_render_pipelining_decision.md`
- Kanban: parking lot `[RENDER-PIPELINING]` (R6-R7 timing)
- This doc remains the canonical design source.

---

## 17. V1 merge — architectural cleanup arc

### 17.0 Why this section was rewritten (2026-06-12)

The original §17 (12 Jun morning) was a 4-item punch list: Tree==World, Resources, module conversion, Pong cleanup. That list assumed a much smaller correction — preserving most of the R6 managed Framework and tightening four loose ends.

The afternoon 2026-06-12 review (user-led) surfaced that the R6 work was structurally divergent from the project's established conventions in ways the 4-item list didn't capture. The actual state we have to fix before `feat/runtime-v2` merges:

1. **An entire managed Framework was built from scratch** (`KernelEngine.Framework` C#) that **duplicates the in-progress native framework migration** (`src/c/kernel/include/kernel_engine/framework/` + `src/cpp/framework/`). The native side already has `ke_scene_tree`, `ke_scene_loader`, `ke_input_actions`, `ke_*_render_system`, `ke_resource_cache`, `ke_mesh_asset_system`, `ke_asset_resolver`. The managed Framework I built reimplements every one of those in pure C#, diverging in behavior.
2. **The native framework plugin's `.cpp` files are bastardized**: STL everywhere (`std::mutex`, `std::condition_variable`, `std::vector`, `std::string`, `std::filesystem`, anonymous namespaces, `toml++` for parsing), reinvented synchronization primitives (a `Future` with `std::mutex` + `condition_variable` in `resource_queue.cpp`). Only `scene_tree.c` and `resource_cache.c` follow the C-plugin pattern; everything else is C++ in a `.cpp` pretending to be a C-ABI plugin.
3. **Header layout violates the established plugin precedent.** Render's create header lives at `src/cpp/render/bgfx/include/kernel_engine/render/bgfx/bgfx_render.h` (plugin-include). Runtime's create header lives at `src/c/kernel/include/kernel_engine/kernel/runtime/runtime_create.h` (kernel-include — wrong). Flecs is in the same wrong place. Framework's headers are at `src/c/kernel/include/kernel_engine/framework/` (missing the `kernel/` segment that render uses).
4. **Legacy `ke_world` + `ke_ecs_registry` + `ke_system` + `ke_variant` + `ke_component_field` are still in `kernel/world/`**, dead but not deleted. Native framework headers all still take `ke_world*` instead of the new `ke_ecs*`+`ke_runtime*` pair.
5. **`InternalsVisibleTo` was added by R6 work** (`KernelEngine.Ecs.Flecs.csproj` exposes internals to Framework + Runtime + tests). The project's established pattern is `public ke_X* Native` (precedent: `Allocator.Native`). `InternalsVisibleTo` is banned.
6. **`IntPtr NativeHandle` on `IEcs` and `IEcsFactory` were added to `Kernel.Abstractions`** during my §17.1 rush — both leak C-ABI / runtime-composition details into the language-agnostic contract layer.

This section replaces the original 4-item punch list with the **full reconciliation plan** the V1 merge actually needs. The original items are folded into the larger plan; see §17.5.

The plan is bigger and slower than the morning version, but **the user explicitly accepted up to a year of delay if that's what doing this correctly costs**, because: this is not in production, and "make it ship now" produces architectural debt that ages the engine. The same shape that ships into `main` is the shape every future plugin author writes against — every shortcut here becomes a workaround they have to learn.

#### Critical context for the C rewrite: two sources, neither sufficient alone

A trap to avoid (already caught by the user on 2026-06-12): when phase C rewrites the framework plugin in C, **the cpp framework alone is NOT a sufficient reference**. The cpp framework was built **before runtime V2 landed**. Its design decisions are centered on the now-deleted `ke_world` (legacy aggregator with sparse-set ECS + integrated tick), use the legacy `ke_system` model, and predate the phase-based runtime scheduler. Translating cpp → c 1:1 carries those pre-V2 decisions forward, which is exactly what we're trying to escape.

The R6 managed Framework (`KernelEngine.Framework` C#, built during this session) is the OTHER reference. It was built **after runtime V2**, so its shape — how systems register with `ke_runtime`, how queries go through `ke_system_ctx`, how worlds isolate via per-instance ecs, how contributors order via phases — is V2-compatible. But it lacks lower-level mechanics the cpp side already has (path resolution rules for scene_loader, TOML schema details for input_actions, material file format, asset resolver heuristics, etc.) — things I never reimplemented managed because they're framework-internal mechanics, not user-facing API.

**The C rewrite synthesizes both sources, plus applies the doctrine (17.1) where neither source had it right.** Mechanics from cpp; runtime-V2 shape from managed; STL elimination + scheduler-based sync from the doctrine. Phase C's per-file plan must reference both sources explicitly so the synthesis is conscious, not accidental.

#### The native framework API itself may need revision

A second trap: the native framework headers (scene_tree.h, scene_loader.h, the render_system.h family, input_actions.h, resource_cache.h, etc.) were designed against `ke_world*` (the legacy aggregator with sparse-set ECS + integrated tick + legacy system graph). Their vtable shapes, parameter lists, lifecycle hooks, and division of responsibilities ALL reflect that model. The user-stated point (2026-06-12): swapping `ke_world*` for `ke_ecs*` in a parameter list is the surface-level change; the contract design underneath may also need to change.

Concrete examples of what may need revisiting (to confirm during B1):
- `scene_tree.h` exposes `find_node` with path resolution. Path resolution might better live in a higher-level helper if scene_tree is supposed to be primitive-shaped; or stay where it is if precedent justifies. Open to revision.
- `scene_loader.h` returns a loaded scene description as a passive structure today (inferred — to verify in audit). In the V2 model, scene loading might register systems directly with the runtime instead of returning data; or stay declarative. Open to revision.
- `*_render_system.h` family had its register/dispatch shape designed around the legacy tick (one update method per frame). With phased runtime, each render system is registered into `RuntimePhase.Extract` (or similar) with a `(ke_system_ctx*, dt)` callback. The contract surface might collapse — possibly the `*_render_system.h` headers don't even need to exist as vtable contracts; they may become simple register helpers in the framework plugin's API.
- `input_actions.h` may or may not need its current shape — depends on how it integrates with `ke_runtime` phases.

Phase B1 is therefore not a mechanical "find/replace `ke_world*` with `ke_ecs*`" pass. It is a per-header contract review pass: for each header in `kernel/framework/`, decide what the V2-correct contract looks like, write it, then phase C builds the implementation against the revised contract.

The contract review uses the same two sources as the implementation rewrite: the existing cpp/header pair (for what was needed pre-V2) + the R6 managed Framework (for what makes sense post-V2). Phase B1 lands the revised contracts; phase C lands the new implementations.

### 17.1 Doctrine locked by this arc

The decisions below are committed for V1 and don't change between phases. They drive the phase plan in §17.2.

#### 17.1.1 World is a native concept, owned by the framework plugin

A "world" — the unit of isolation that holds an ECS storage instance, a runtime scheduler, and a scene tree — is a **native concept**, exposed as `ke_world` from the framework plugin (`src/c/framework/`). NOT the legacy `kernel/world/world.h` `ke_world` (which is deleted in B0); this is a new, smaller aggregator.

Shape (subject to design refinement during B2):
```c
typedef struct ke_world ke_world;  // opaque

ke_result ke_world_create(
    ke_allocator      *alloc,
    ke_task_scheduler *task_scheduler,
    ke_ecs            *ecs,        // caller pre-creates with its chosen impl
    ke_world         **out_world);

ke_ecs        *ke_world_ecs(ke_world *w);
ke_runtime    *ke_world_runtime(ke_world *w);
ke_scene_tree *ke_world_scene_tree(ke_world *w);
void ke_world_destroy(ke_world *w);
```

Why native: because every binding (C#, Lua, future LOLCODE etc.) wraps the same world. The aggregator can't live only in C# without each binding reimplementing it. It belongs to the engine's user-facing contract.

Multi-world: `ke_world_create` called N times. Each instance is independent. The task scheduler is shared across worlds (it's a kernel primitive).

#### 17.1.2 Runtime stays a standalone plugin; framework depends on it

`ke_runtime` (the system scheduler with phases + parallel waves + defer queue) remains a separate plugin at `src/c/runtime/`. Framework links it as a dependency. Rationale:

- Runtime is genuinely useful without framework (minimal game loops, tests, future bindings that want to roll their own scene-graph).
- Examples like `00_runtime_minimal` and `01_runtime_clear_color` validate runtime-without-framework. They survive the migration.
- Keeping it separate enforces the layer boundary — framework can't reach into runtime internals.

The note "runtime passa a compor framework" (user, 2026-06-12) is interpreted as *composition*, not physical merging: framework depends on runtime, framework's `ke_world_create` instantiates a runtime internally, but the runtime plugin's source stays in its own folder.

#### 17.1.3 Header layout: plugin pattern enforced

Established precedent (render's bgfx plugin):
- **Contract** (vtable + types) lives in `src/c/kernel/include/kernel_engine/kernel/<domain>/`. Example: `kernel/render/render.h`.
- **Plugin create** lives in `src/<plugin-path>/include/kernel_engine/<domain>/<plugin>/`. Example: `src/cpp/render/bgfx/include/kernel_engine/render/bgfx/bgfx_render.h`.

Current violations that A1/A2 fix:
- `src/c/kernel/include/kernel_engine/kernel/runtime/runtime_create.h` → `src/c/runtime/include/kernel_engine/runtime/runtime_create.h`.
- `src/c/kernel/include/kernel_engine/kernel/world/ke_ecs_flecs.h` → `src/c/ecs/flecs/include/kernel_engine/world/ke_ecs_flecs.h`.
- `src/c/kernel/include/kernel_engine/framework/*.h` → split per file:
  - Contracts (vtable + types): `src/c/kernel/include/kernel_engine/kernel/framework/`.
  - Plugin creates: `src/c/framework/include/kernel_engine/framework/`.

Plugin domain folder convention: header path inside the plugin uses `kernel_engine/<domain>/[<plugin>]/`. The `<plugin>` segment is included when multiple plugins implement the same domain (render: bgfx today, wgpu/vulkan tomorrow). When a domain has only one plugin (today: flecs for ECS, in-house for runtime, framework itself), the `<plugin>` segment is omitted — `kernel_engine/runtime/runtime_create.h`, not `kernel_engine/runtime/in_house/runtime_create.h`.

#### 17.1.4 Framework plugin is implemented in C, not C++

Established precedent: `scene_tree.c` and `resource_cache.c` already exist as pure C in `src/cpp/framework/src/`. Every other file there is `.cpp` with STL idioms — that was a mistake by the previous implementer.

Decision: rewrite every `.cpp` in framework as `.c`, **reusing the existing logic** (which is largely correct) but eliminating:
- `std::mutex`, `std::condition_variable`, `std::thread`, `std::future` — replaced by scheduler primitives (see 17.1.6).
- `std::vector`, `std::deque`, `std::string`, `std::filesystem` — replaced by `ke_allocator` + raw arrays + char buffers.
- `toml++` — replaced by a C TOML library (choice deferred to phase C; tomlc99 is the leading candidate, MIT, single-file).
- Anonymous namespaces — replaced by `static` functions.
- `new` / `delete` — replaced by `ke_allocator`.

Move to `src/c/framework/src/`. Drops `src/cpp/framework/` entirely.

Why C: framework is a C-ABI plugin. Its public surface is C. Its implementation pretending to be C++ is gratuitous — it just makes the binary larger, harder to bind to other languages (Lua / future LOLCODE want C symbols, not C++ name-mangled ones, even if `extern "C"` works at the create boundary), and invites STL contagion across the codebase.

#### 17.1.5 No `InternalsVisibleTo`

Banned. Cross-binding access uses public `Native` pointers, precedent `Allocator.Native` (which is `public ke_allocator*`). Existing entries in `KernelEngine.Ecs.Flecs.csproj`, `KernelEngine.Runtime.csproj`, `KernelEngine.Kernel.csproj` are debt; each requires inspection of every internal member the friend was using, promotion to public, then removal of the entry. Phase E handles this.

#### 17.1.6 No mutex / condvar / std::thread in framework — scheduler does sync

`std::mutex` + `std::condition_variable` in `resource_queue.cpp` is the canonical wrong: it reinvented a Future on top of the standard library while the kernel ships `ke_task_scheduler` with `wait_for_task` already. Two replacement patterns suffice for everything the current code does:

1. **Async completion (Future-like)**: submit the work as a task to `ke_task_scheduler`; caller polls or blocks via `ke_task_scheduler->wait_for_task(handle)`. Zero mutex.
2. **Producer-consumer ordering**: register producer in phase N, consumer in phase N+1; the runtime guarantees barrier between phases. Zero queue synchronization.

The threading rule applies to **every plugin written from now on**, not just framework. The existing kernel threading primitives (`ke_semaphore`, `ke_frame_sync`, `KeFrameSync`) are themselves slated for deletion in Z6 — the scheduler is the synchronization layer.

#### 17.1.7 Managed naming: `World` (aggregator) + `SceneTree` (wrapper)

C# Framework exposes:
- **`World`** — wrapper of `ke_world*`. The user-facing aggregator. Owns `Ecs` + `Runtime` + `SceneTree` accessors. `public ke_world* Native` (precedent: `Allocator.Native`). Multi-world = `new World(...)` multiple times.
- **`SceneTree`** — wrapper of `ke_scene_tree*`. The scene-graph API (`AddNode`, `DestroyNode`, `Find`, traversal). Lives inside a `World`; `world.SceneTree` exposes it.

The class I wrote during R6 as `Tree` (managed scene-graph + per-tree ECS + behaviors + labels registry) is **deleted**. Its responsibilities go either to `SceneTree` (the parts that wrap `ke_scene_tree`) or to `World` (the parts that aggregate the world's pieces).

"Tree==World" from the original §17.1 is reformulated: **World is the unit of isolation; SceneTree is the part of a World you talk to most**. Multi-world = multi-World. The earlier formulation "Tree owns its own IEcs" was correct in spirit but wrong in placement — that ownership is World's, not SceneTree's.

### 17.2 Phase plan

Each phase is one atomic commit (occasionally two if the diff is too big for one review), validated before the next starts. The user reviews and approves each phase boundary before proceeding.

#### 17.2.A1 — Native framework headers under `kernel/framework/`

Move `src/c/kernel/include/kernel_engine/framework/*.h` → `src/c/kernel/include/kernel_engine/kernel/framework/*.h`. Update every `#include` in native source and bindings. Keep `framework_export.h` (the dllexport macro is still needed because framework is a plugin); just move its location too.

**Validation**: full native build green; existing native tests pass.

#### 17.2.A2 — Plugin create headers move to plugin-include

Three concurrent moves (one commit because they're symmetrical changes):
- `src/c/kernel/include/kernel_engine/kernel/runtime/runtime_create.h` → `src/c/runtime/include/kernel_engine/runtime/runtime_create.h`. Update C# Runtime binding's clang-sharp .rsp.
- `src/c/kernel/include/kernel_engine/kernel/world/ke_ecs_flecs.h` → `src/c/ecs/flecs/include/kernel_engine/world/ke_ecs_flecs.h`. Update C# Ecs.Flecs binding's .rsp.
- `src/c/kernel/include/kernel_engine/kernel/framework/<header>.h` per file: split vtable+types (stays in `kernel/framework/`) from create function (moves to `src/c/framework/include/kernel_engine/framework/<x>_create.h`).

For each moved create header, mirror in the corresponding C# binding's `.rsp` (precedent: bgfx_render binding `.rsp`).

**Validation**: native build green, native tests pass, all C# bindings rebuild.

#### 17.2.A3 — `KernelEngine.Runtime` csproj structure

Decision deferred to this phase whether to (a) fold `KernelEngine.Runtime` into `KernelEngine.Framework` as a sub-namespace, or (b) keep it as a separate csproj that Framework depends on. The native side is "runtime is a separate plugin", so (b) mirrors more honestly. Lean (b) unless ergonomics suffer.

ClangSharp regen for both Runtime + Framework + Ecs.Flecs bindings to pick up the new header locations.

**Validation**: C# build green, examples 00_runtime_minimal + 01_runtime_clear_color still run.

#### 17.2.B0 — Delete legacy `kernel/world/` AND rename the folder/namespace

User-explicit safety constraint (2026-06-12): the new `ke_world` aggregator (B2) must NEVER coexist in the tree with the legacy `ke_world`. Even momentarily. The repo never holds two `world.h` files. Therefore B0 not only deletes the legacy symbols but **also renames the kernel folder + namespace away from the word "world"** so the future framework `world.h` lives in a different namespace from anything that ever existed in kernel.

Rename target: `kernel/world/` → **`kernel/ecs/`**. Reflects what's left in the folder after deletions (the `ke_ecs` storage contract). The kernel side now has zero "world" reference; "world" exclusively becomes a framework concept (B2).

Inventory pass on `src/c/kernel/include/kernel_engine/kernel/world/` + `src/c/kernel/src/world/`:

| File | Status | Action |
|---|---|---|
| `ke_ecs.h` | New contract (alive) | **Move** to `kernel/ecs/ke_ecs.h`. Update every consumer's `#include`. |
| `ke_ecs_flecs.h` | Plugin create (alive, wrong location) | Moved by A2 to `src/c/ecs/flecs/include/kernel_engine/world/ke_ecs_flecs.h`. Reconsider that destination too — if "world" is being purged from kernel, the plugin namespace also shifts to `kernel_engine/ecs/`. Update accordingly. |
| `components.h` | TBD — inspect content | Audit: if it defines POD components shared across new framework, decide whether they live under `kernel/ecs/components.h` (storage-adjacent) or move into framework. If legacy registry fields, delete. |
| `world.h` (legacy `ke_world`) | Dead | **Delete** |
| `ecs.h` (legacy `ke_ecs_registry` sparse-set) | Dead | **Delete** |
| `system.h` (legacy `ke_system`) | Dead | **Delete** |
| `variant.h` (legacy `ke_variant`) | Dead | **Delete** |
| `component_field.h` (legacy field descriptors) | Dead | **Delete** |
| `src/c/kernel/src/world/ecs.c` (legacy impl, 407 lines) | Dead | **Delete** |
| `src/c/kernel/src/world/world.c` (legacy impl, 372 lines) | Dead | **Delete** |
| `src/c/kernel/src/world/` (folder, empty after deletes) | — | **Delete** folder; if `ke_ecs.h` impl survives somewhere on the kernel side it lives under `src/c/kernel/src/ecs/`. |

Cascade: grep every consumer of `world.h`, `ecs.h` (legacy), `system.h`, `variant.h`, `component_field.h`. Native framework `.cpp` files DO consume them today (they all take `ke_world*`); they break temporarily. Bindings `.rsp` files that reference the renamed paths break. Both are accepted as expected breakage that B1 + the path-rename sweep fix.

**Validation**: native build green AFTER B1 has rewritten the framework contracts against the renamed namespace. B0 alone is a build-broken intermediate state. In practice B0 + B1 land together as one commit (or two tightly sequenced commits where the second is "fix consumers").

**Safety invariant after B0+B1 lands**: the string `ke_world` does NOT appear anywhere in the tree. When B2 reintroduces `ke_world` (as a NEW framework-plugin aggregator), the tree's only "world" is the new one. No accidental cross-pollination possible.

#### 17.2.B1 — Contract review: native framework headers redesigned for V2

NOT a parameter swap. Each header in `kernel/framework/` is reviewed end-to-end:

For each header:
1. Inspect the current contract (vtable methods, params, lifecycle).
2. Cross-reference with the corresponding R6 managed equivalent (if I built one — e.g. my `SceneLoader.cs` against `scene_loader.h`).
3. Cross-reference with how the existing cpp uses the contract internally (what it actually depends on vs. what's accidental).
4. Apply the doctrine: opaque handles only; system registration through `ke_runtime`; component access through `ke_system_ctx`; no `ke_world` parameters because the new model has no ke_world struct (the new `ke_world` aggregator in framework plugin is just a holder; framework primitives like scene_tree don't depend on it).
5. Write the revised contract.

The redesign per header may keep the vtable shape, may narrow it, may widen it, may collapse the whole header into a register-helper if the V2 model makes the vtable unnecessary. Each decision is recorded in the commit message + a one-line entry in this section once the phase commits.

Affected headers (the audit will find any I missed):
- `scene_tree.h` — vtable likely stays close to current; create takes `ke_ecs*` instead of `ke_world*`; `destroy_all` lifecycle reviewed against tree teardown semantics in R6 managed.
- `scene_loader.h` — review against R6 managed `SceneLoader`. Decide: returns passive scene description (legacy shape), or directly drives `ke_scene_tree` + registers systems (managed-style)? Open.
- `*_render_system.h` family — strongly suspect these collapse to register-helpers (no opaque vtable, just `ke_camera_render_system_register(runtime, ecs)` etc.) because R6 managed contributors were stateless functions that read ECS + write packet, and that pattern doesn't need a vtable. To confirm.
- `input_actions.h` — substantial existing impl (143 blocos). Review per-method whether actions are queried directly (current shape) or whether they fit into the runtime's input phase as system-injected resources.
- `resource_cache.h`, `resource_queue.h` — review against R6 managed `PongResources`-style and the broader Resources concept (originally §17 morning point 2; now folded into the wrapper design).
- `mesh_asset_system.h`, `asset_resolver.h`, `material_file.h`, `mesh_shape.h` — review against R6 managed `ModelExtensions.cs` and the asset-loading path that Pong + example 12 + 13 exercise.

**Validation**: native build green after B1 + B2 + the start of C land together (the contracts change requires the new `ke_world` aggregator + at least one C impl to be useful).

In practice B1 contracts are written first, B2 lands the aggregator, then C implementations roll out per file, with the native build broken until enough of C lands to satisfy the test suite.

#### 17.2.B2 — New `ke_world` aggregator in framework plugin

Introduce `src/c/framework/include/kernel_engine/framework/world.h` (contract — opaque `ke_world` + accessors) and the create header `src/c/framework/include/kernel_engine/framework/world_create.h` (or fold into `world.h` if precedent does the same). Impl: `src/c/framework/src/world.c` (pure C from day one).

`ke_world_create` takes `(alloc, task_scheduler, ecs, &out_world)`. Internally creates the runtime + scene_tree on top of the ecs. Owns them.

Add at least one native integration test that:
- Creates two worlds in the same process.
- Spawns an entity in each.
- Confirms they don't see each other's entities.
- Destroys one; the other keeps working.

**Validation**: native test multi-world passes.

#### 17.2.C — Framework plugin implementation in C, built against B1's revised contracts

Each file in the new `src/c/framework/src/` is written from scratch (not translated from cpp), implementing the contract revised in B1, **synthesizing logic from three sources**:

1. **The R6 managed file** (the V2-compatible shape — e.g. my `KernelEngine.Framework.SceneLoader.cs` against the new `scene_loader.h`).
2. **The legacy cpp file in `src/cpp/framework/src/`** (lower-level mechanics — path resolution, TOML parsing details, file format specifics, etc.).
3. **The doctrine** (17.1: no STL, no mutex, scheduler-based sync, `ke_allocator` for memory, public Native pattern, C-only).

For each file, the plan documents:
1. Which existing sources contribute what (managed shape vs cpp mechanics vs new doctrine pieces).
2. STL/std elements being replaced and with what (the substitutions table from 17.1.4 + 17.1.6).
3. TOML parser swap (where applicable): `toml++` → C TOML lib chosen at start of phase (tomlc99 leading candidate).
4. Lifecycle hooks against the revised contract.
5. Final destination: `src/c/framework/src/<name>.c`.

Audit order (smallest to biggest, to build confidence):
- `material_file.cpp` (7 blocos)
- `asset_resolver.cpp` (~18 blocos)
- `camera_render_system.cpp` (~18 blocos)
- `mesh_render_system.cpp` (~13 blocos)
- `mesh_asset_system.cpp` (~20 blocos)
- `light_render_system.cpp` (~32 blocos)
- `mesh_shape.cpp` (TBD)
- `scene_loader.cpp` (~83 blocos — substantial)
- `resource_queue.cpp` (mid-size, but has the std::mutex / Future to redesign first)
- `input_actions.cpp` (~143 blocos — biggest, TOML-heavy)

Each rewrite is a commit. Each commit validates the corresponding native test slice.

`src/cpp/framework/` folder is deleted at the end of phase C.

**Validation**: native build green, all native tests pass, the file `scene_tree.c` + `resource_cache.c` continue to work unchanged (precedent files that the rewrite mimics).

#### 17.2.D — Managed wrappers replace R6-era managed implementations

Order: smallest dependency cone first.

- **D1**: `KernelEngine.Framework.World` wrapper of `ke_world*`. `KernelEngine.Framework.SceneTree` wrapper of `ke_scene_tree*`. Replaces my `Tree` class.
- **D2**: `KernelEngine.Framework.SceneLoader` wrapper of `ke_scene_loader*`. Replaces my managed scene loader.
- **D3**: `KernelEngine.Framework.InputActions` wrapper of `ke_input_actions*`. Replaces my managed `InputActionMap`.
- **D4**: render system wrappers (`CameraRenderSystem`, `LightRenderSystem`, `MeshRenderSystem` — wrappers that register the native systems with the world's runtime). Replaces my `IFrameContributor` family.
- **D5**: resource cache, mesh asset system, asset resolver, material file wrappers. Replaces my `ModelExtensions`, `PongResources`-style classes.

Each replaces the corresponding R6-era managed class, validated end-to-end against the example suite (00–16 + Pong).

After each Dn, the corresponding R6 managed file in `KernelEngine.Framework/` is deleted.

**Validation per Dn**: examples + Pong continue to render and behave identically.

#### 17.2.E — Cleanup the R6 abstractions mess

- Delete `IEcsFactory` from `KernelEngine.Kernel.Abstractions`.
- Delete `IntPtr NativeHandle` from `IEcs`.
- Promote `FlecsEcs.Native` from internal to public (precedent: `Allocator.Native`).
- Drop `InternalsVisibleTo` entries from `KernelEngine.Ecs.Flecs.csproj`, `KernelEngine.Runtime.csproj`, `KernelEngine.Kernel.csproj` (one inspection pass per entry: confirm no internal access remains).
- Update examples 00–16 + Pong: stop registering `IEcsFactory`. Instead register `FlecsEcs` directly + create World composing it.

**Validation**: full solution build, every example + Pong rebuilt and ran.

#### 17.2.F — Font / Label native completion + final validation

Font / Label have no native equivalent today. R6 shipped a managed `Font` + `Label` + `LabelContributor` because UI/text is debt on the native side.

Per user direction (2026-06-12): Font/Label IS part of the runtime V2 task, but lands LAST within the arc. Concretely:
- Native: `ke_font` + `ke_label` in framework plugin (or equivalent named scheme matching scene_tree precedent).
- C# wrappers replace my managed Font/Label/LabelContributor.
- Pong + example 14 + 15 + 16 keep working visually.

Final validation pass: smoke visual every example + Pong. Full test suite. Native + C# coverage report. Merge-ready.

### 17.3 Doctrine writeups (memory + global rules created during this arc)

- `feedback_search_precedents_before_inventing.md` — top-of-mind project rule. Every structural decision starts with "find an existing example in the repo".
- `feedback_no_internals_visible_to.md` — `InternalsVisibleTo` banned. Public `Native` pointer is the precedent.
- `feedback_consult_legacy_before_rewriting.md` — preceded this arc, applies fully here.
- `project_tree_equals_world_doctrine.md` — superseded by 17.1.1 + 17.1.7 in this section. Memory file kept as history.

### 17.4 What was originally on the punch list (folded in)

- **Original 17.1 Tree==World** → folded into 17.1.1 (native World) + 17.1.7 (managed naming).
- **Original 17.2 Resources** → folded into D phases (Resources are how D4/D5 expose materials, fonts, cross-script refs).
- **Original 17.3 Module conversion** → folded into the wrapper redesigns in D + E (composition style is uniform IRuntimeModule once wrappers settle).
- **Original 17.4 Pong cleanup** (Ball.Position, Wall.Scale, Tree.Find) → folded into D-phase validation (the cleanups become bugs that show up when D wrappers replace the R6 versions, and the rewrite makes the right behavior natural).

### 17.5 What's NOT in this merge arc (explicit non-goals)

- §15 NodeBehavior codegen — manual surface ships in V1; codegen is post-merge.
- Tier Z6 (FramePacket bridge replacement + threading/FrameSync deletion) — V2-render territory, lands after V1 merge.
- Render core breakup (PBR-as-plugin, L3-L7 doctrine) — V2-render.
- Multi-window / multi-camera — not unblocked by 17.1; deferred.
- `Tree.Find` (now `SceneTree.Find`) — kept as escape hatch; not used as the default after D phases land.
- ~~Folder rename `kernel/world/` → `kernel/ecs/` — cosmetic, can defer post-merge.~~ → done in B0 (safety constraint, not cosmetic; see 17.6).

### 17.6 Execution log (live — this section is the single source of truth for branch state)

Branch: `feat/runtime-v2`. Read this section first when continuing in a fresh session; everything below the doctrine in 17.1 is recorded here as it actually happened, including phases that diverged from the original plan.

#### 17.6.1 Phases shipped

Listed in branch order; each row is one atomic commit.

| Phase | Commit | What landed |
|---|---|---|
| **A1** | `92e26e6` | Move native framework headers `src/c/kernel/include/kernel_engine/framework/` → `kernel_engine/kernel/framework/`. Conforms to "contracts at `kernel_engine/kernel/<domain>/`" precedent. Rewrites every native `#include`. `.rsp` / Lua / docs deferred to final sweep. |
| **A2** | `081787e` | Extract plugin create factories to plugin-include paths. Runtime: `kernel/runtime/runtime_create.h` → `src/c/runtime/include/kernel_engine/runtime/runtime_create.h`. Flecs ECS: same shape into `src/c/ecs/flecs/include/kernel_engine/ecs/ke_ecs_flecs.h`. Framework: 10 contracts each split — vtable+types stay in kernel-include, `*_params` + `*_create()` move into `src/cpp/framework/include/kernel_engine/framework/<name>_create.h` per file. |
| **A3** | (folded) | C# csproj structure decision (Runtime stays as its own csproj, not merged into Framework). No code change; recorded here for completeness. |
| **B0** | `660d4aa` | Delete legacy `ke_world` (header + impl + test) AND rename folder + namespace `kernel/world/` → `kernel/ecs/`. Safety invariant locked: the string `ke_world` does not exist anywhere in the tree after B0 until B2 reintroduces it as a framework concept. Cascade: examples 02/03 disabled (consumed legacy), framework plugin disabled (depended on legacy world API), 8 framework-backed tests in `tests/c/kernel/CMakeLists.txt` disabled, `test_framework_integration` disabled. Build stays green for the remaining targets. |
| **B1** | (design only) | Per-header contract review of all 13 framework headers. Decisions captured in memory `project_b1_framework_contracts.md` and below in 17.6.2. No code change. |
| **B1.5** | `a70e3a1` | Audit fallout: move framework primitives to the kernel domains they actually belong in. `resource_cache.h` → `kernel/resource_cache/` (new domain). `mesh_shape.h` → `kernel/asset/`. `asset_resolver.h` → `kernel/asset/`. The kernel/framework/ folder shrinks to genuinely-framework concepts (scene_tree, scene_loader, input_actions, material_file POD, framework_export). |
| **B2** | `574f543` | New native `ke_world` aggregator in framework plugin. World is a **vtable** (consistent with render/window/ecs/runtime/scene_tree precedent). Framework plugin exports exactly ONE symbol per factory header — `ke_world_create` from `src/c/framework/include/kernel_engine/framework/world_create.h`. Ownership: world OWNS ecs+runtime+scene_tree; world BORROWS allocator+task_scheduler+logger. Cascade-destroy in reverse-create order. `scene_tree` allowed NULL in `ke_world_params` during C-phase transition; tightened when C-phase 3 reintroduces scene_tree impl. New `src/c/framework/` plugin folder + CMakeLists + multi-world integration test (`tests/integration/cpp/test_world.cpp`, 2 tests). |
| **C-phase 1** | `df16216` | Port `asset_resolver` to pure C in the new framework plugin. Vendored **tomlc99** at `src/c/framework/third_party/tomlc99/` (MIT, ~1.5k LoC single .c+.h pair; precedent for plugin-local vendored deps when vcpkg doesn't carry the relevant C library). `material_file.h` reduced to POD-only — parse is now an internal helper inside `asset_resolver.c`, reached externally only via `resolver->resolve_material()`. `mesh_shape.h` reduced to POD-only similarly — bake/free are internal helpers in `src/c/framework/src/mesh_shape.c`, reached via `resolver->resolve_mesh()`. Both decisions follow the convention "plugin factory headers export exactly one symbol; everything else flows through vtables". |
| **C-phase 2** | `9b86df2` | Promote `resource_cache` to **kernel built-in** (precedent: `ke_allocator_malloc_create`). Impl lives in `src/c/kernel/src/resource_cache/resource_cache.c`. Tier 1 decisions applied: `destroy_fn` + `destroy_ctx` move from per-`register_resource` to **per-cache** (set at create via `ke_resource_cache_params`); `cache_insert` returns `ke_result` (errors on duplicate key) instead of silent overwrite; `register_resource` simplified to `(self, handle)`. Tests rewritten for the per-cache model (19 cases). |
| **C-phase 3** | `84831b3` | Port `scene_tree` to pure C in the framework plugin. New header `kernel/framework/components.h` declares POD vocabulary (`ke_transform_component`, `ke_hierarchy_component`, `ke_name_component` + name constants). `scene_tree_create()` signature change: takes `ke_ecs*` directly (no longer `ke_world*`), idempotent via `component_lookup` so multiple scene_trees on the same ecs share cids. Critical bug fix during impl: **flecs invalidates pointers across `ecs_get_mut_id`** when the entity moves to a new archetype — captured `component_add` calls must complete BEFORE any `component_get` reads or sibling-chain writes (test `DestroyNode_UnlinksFromMiddleOfChain` surfaced it). Test rewrite: 19 cases driven through the public scene_tree API only (no legacy world internals). |
| **C-phase 4** | `0cceb34` | Render component vocabulary inlined into `components.h`: `ke_camera_component`, `ke_directional_light_component`, `ke_point_light_component`, `ke_spot_light_component`, `ke_mesh_component` + name constants. LEGACY `*_render_system.h` contracts + their `.cpp` impls + their `_create.h` deleted entirely (12 files). Rationale: the LEGACY systems wrote into `ke_frame_packet`; no consumer left on the branch (`01_runtime_clear_color` uses `BgfxRenderModule` direct; only the parallel `KernelEngine.Framework.Legacy` managed assembly referenced them and that's being retired). When §16 component snapshot lands in R6+, render plugins read these PODs directly from the back buffer; no extract-systems-shaped middle layer ever returns. |
| **C-phase 4.5** | `5aa72f2` | Housekeeping: delete orphan `src/cpp/framework/src/` files left over from C1-C3 (asset_resolver.cpp, material_file.cpp, mesh_shape.cpp, resource_cache.c, scene_tree.c — all already ported elsewhere). Also delete `resource_queue.cpp` + its create header + the kernel-include contract per Tier 1's "resource_queue is replaced by direct `ke_task_scheduler->submit_to(thread, fn) + wait_for_task`" decision. After this commit only `input_actions.cpp` + `scene_loader.cpp` (+ their create headers) remain in `src/cpp/framework/`. |

#### 17.6.2 Design decisions surfaced during execution (not in the original 17.1)

These came up while executing the plan and are now locked. Recorded here so a fresh session doesn't re-litigate them.

1. **Plugin contract headers contain NO export-macro-decorated symbols** — they declare vtable shapes only. Plugin create headers (in plugin-include paths) are the only place `KE_*_API` appears, and each create header exports exactly one symbol (the factory). Established in B2 design; framework's own `ke_world_create` is the canonical example, every other plugin (bgfx, glfw, flecs) follows the same shape. (Note: kernel built-ins like `ke_allocator_malloc_create` ARE allowed to live in the kernel contract header — kernel headers self-export by precedent. Only plugin-side contracts are pure-vtable.)
2. **World is a vtable** (not a concrete type). Framework plugin is the canonical implementation; alternative frameworks (ECS-pure-without-scene-tree, etc.) ship by exporting their own `ke_world_create` returning a different vtable shape. There is NO `ke_framework` vtable — the framework plugin has no runtime object identity, only its `ke_world_create` factory (matches bgfx/glfw/flecs precedent: render plugin has no "render plugin object", just `ke_render_bgfx_create()`).
3. **World ownership model** *(revised 2026-06-13 — see decision #9)*: world BORROWS ecs + runtime + scene_tree. World BORROWS allocator + task_scheduler + logger. `world->destroy(world)` frees only its own state (apply_registry + state block). **The host owns every resource it creates and destroys each one independently.** In C#, the `World` wrapper IS the host — it creates and owns `FlecsEcs` + `Runtime` + `SceneTree`, and `World.Dispose()` cascades teardown of those managed wrappers before destroying the ke_world_state. `IEcs` and `IRuntime` are **not** DI singletons; they are created by and owned by the `World` wrapper.
4. **Vendoring precedent for plugin-private C deps**: when vcpkg doesn't carry a relevant pure-C library, the plugin vendors it inside `src/c/<plugin>/third_party/<lib>/` with a `VENDOR.md` recording upstream + license + sync date. Established by tomlc99 in C-phase 1. Contained: never leaks to kernel or sibling plugins; another plugin needing the same lib either depends on this plugin's include path (when natural) or vendors its own copy.
5. **`scheduler is the synchronization`** (from 17.1.6) is binding for new code, including transitional frameworks. `resource_queue` is the canonical proof — it reinvented a `std::mutex`+`condition_variable` Future on top of an engine that ships `ke_task_scheduler->wait_for_task`. Deleted in C-phase 4.5; replacement is direct scheduler dispatch (`submit_to(target_thread, fn, ctx) → handle` + `wait_for_task(handle)`).
6. **Framework partition audit** (after Tier 2, executed in B1.5): apply the lens "opinion vs primitive" to every framework concept. Things you could swap by choosing a different framework on top of this kernel → framework. Things every framework on top of this kernel would want the same way → kernel. `resource_cache`, `mesh_shape`, `asset_resolver` failed the opinion test and migrated to kernel domains. `scene_tree`, `input_actions`, `scene_loader`, `material_file`, `components.h`, `world` are opinions and stay framework. Legacy render systems are transitional infrastructure (frame_packet bridge), not opinion — deleted.
7. **flecs archetype move invalidates pointers** (surfaced in C-phase 3): every `ecs_get_mut_id` (which `ke_ecs->component_add` + `component_get` route through in our flecs wrapper) can move the entity to a new archetype and invalidate any pointer returned from an earlier call on the SAME entity. Rule for safe entity construction: do all `component_add` calls FIRST, then re-fetch each component via `component_get` before writing data. Adding component to entity X doesn't move OTHER entities (Y, Z, ...) so pointers to siblings/parents stay valid.
9. **"Quem cria, owna" e o modelo de borrow entre vtables** (decidido 2026-06-13): O precedente já estabelecido pelo `ke_runtime` (`ke_ecs *ecs; // borrowed; alive while the system runs` — `runtime.c` l.55 + l.578) é o padrão universal. Nenhuma vtable de implementação deve chamar `->destroy()` em ponteiros que não criou. O `ke_world_create` original alegava "ownership transferred" e cascateava o destroy — isso foi identificado como anomalia sem precedente no projeto e revertido. **Regra fixada**: `world_destroy` libera apenas o que `ke_world_create` alocou (state + apply_registry); ecs/runtime/scene_tree são destruídos por quem os criou. No binding C#: o wrapper `World` assume o papel de host, cria e owna `FlecsEcs`/`Runtime`/`SceneTree`, e `Dispose()` cascateia os três antes de destruir o ke_world_state. Consequência: `IEcs` e `IRuntime` saem do DI como singletons de processo — são membros privados do `World` wrapper, com lifetime atado ao mundo a que pertencem (multi-world funciona naturalmente). **ABI de longo prazo**: Kanban A16 rastreia a split de handles em `ke_ecs` (owner) + `ke_ecs_view` (borrow) para tornar a distinção física na type system C — enquanto não implementado, é convenção documentada.
8. **LEGACY render systems are dead, not transitional** (decided in C-phase 4 after consumer audit): the four `*_render_system` + `mesh_asset_system` impls wrote into `ke_frame_packet`, and no remaining consumer needed that on the branch. They were deleted, not ported. Render in R6+ reads `ke_camera_component`/`ke_*_light_component`/`ke_mesh_component` directly from the per-component snapshot back buffer; no extract layer in between.

#### 17.6.3 Current state — what's in the tree right now

After F-phase (2026-06-13):

- **Native build green** across all plugins. 518/520 tests passing; 2 RuntimeSpike failures are pre-existing (predate this arc).
- **`src/c/framework/`** plugin contains: `world.c`, `asset_resolver.c`, `mesh_shape.c` (internal), `scene_tree.c`, `scene_loader.c`, `input_actions.c`, `components_apply.c`, plus `third_party/tomlc99/`. Factory headers: `world_create.h`, `asset_resolver_create.h`, `scene_tree_create.h`, `scene_loader_create.h`, `input_actions_create.h`. Fully C, no `src/cpp/framework/` remains.
- **`ke_asset_resolver`** vtable gained `resolve_font` + `free_font` slots; `ke_asset_resolver_create` now accepts `ke_font_loader*` alongside `ke_image_loader*`. Font is a resource in the same domain as texture/mesh/material — no separate `ke_font` vtable.
- **`kernel/framework/components.h`** holds the 3D scene vocabulary: transform, hierarchy, name, camera, lights, mesh. No UI components — `ke_label_component` was designed and rejected; see design decision #10.
- **`kernel/asset/`**: `asset_resolver.h` (with font slots), `image_loader.h`, `mesh_shape.h`, `mesh_data.h`, `asset_loader.h`.
- **`kernel/text/font.h`**: `ke_font_loader` vtable + `ke_font_data` / `ke_glyph_metrics` structs. No `ke_font` vtable — loader returns raw data, caller uploads atlas via `ke_render`.
- **C# bindings**: all 14 `.rsp` files regenerated green. `KernelEngine.Framework.Legacy.Native` project deleted (was referencing pre-A1 header paths that no longer exist — F-phase sweep).
- **C# wrappers**: `INativeFontLoader` interface + `FontLoader` implements it. `NativeAssetResolver` accepts `INativeFontLoader?`, new `ResolveFont(path, pixelSize, ...)` method returns `ResolvedFontData : IDisposable`.
- **Label**: stays as managed C# (`Label : Node`, `LabelContributor`, `Font`) — **deliberate debt**. Native port rejected: the entire UI concept (Node3D/Node2D/Canvas/Control hierarchy) will be redesigned post-merge; any native `ke_label` created now would be discarded in that refactor. See design decision #10.
- **C# solution build**: 0 errors, 0 warnings (CA warnings pre-existing and unrelated to this arc).

#### 17.6.4 Design decisions surfaced in F-phase (2026-06-13)

10. **Node hierarchy design locked, impl deferred post-merge** — `Node` → `Node3D` / `Node2D` / `Canvas` / `Control` split is the correct architecture. `Node3D` carries `ke_transform_component`; `Node2D` carries `ke_transform2d_component` (xy + rot + scale, pixel/unit space); `Canvas` is a hierarchy boundary (no transform — breaks 3D/2D transform inheritance chain); `Control` carries `ke_ui_anchor_component`. Rules: Node3D inherits transform only from Node3D parents; Node2D only from Node2D parents; Canvas children can only be Control (scene_loader validates). "Node3D → Canvas → Node3D" is invalid hierarchy. **2.5D / Octopath / billboards use Node3D + billboard rendering flag, NOT Node2D** — 2.5D is 3D world space with sprite art; Node2D is for pure-2D pixel-space games. `ke_label_component` in `components.h` was rejected because: (a) Label is UI, not 3D scene vocabulary; (b) it would embed a raw `ke_font_data*` pointer in an ECS component instead of a font handle; (c) the entire concept is replaced when Canvas/Control lands. Font should be a resource with `ke_font_handle` (uint32_t, like `ke_mesh_handle`) when that milestone arrives.

#### 17.6.5 G-phase — migrate legacy managed classes to native wrappers

**Goal**: replace the Tomlyn-based `Tree`/`SceneLoader` stack in `KernelEngine.Toolkit` with native-backed equivalents, wire Pong as its own `IRuntimeModule`, and retire all reflection-driven property binding.

**Invariants that must hold throughout G-phase (never relax these):**
- `KernelEngine.Framework` knows ECS + Scene only — NEVER knows what a `Node` is.
- `KernelEngine.Toolkit` is the sugar layer — `Node` lives here only.
- No `InternalsVisibleTo`. Cross-layer access through public `Native` pointers.
- No reflection in Node / script code.
- No manual editing of `Generated/` files.
- Entity creation always goes through `World.NativeSceneTree.CreateNode()`, never `IEcsAdapter.CreateEntity()` directly.
- Render is a module — `World`, `IEcs`, `IRuntime`, `NodeWorld` never reference `IRenderer`.

---

##### G1 — NodeWorld replaces Tree in Toolkit (atomic commit)

**What**: create `src/csharp/KernelEngine.Toolkit/Scene/NodeWorld.cs`. This is the Node-aware facade over `World` that replaces the legacy `Tree`.

Constructor: `internal NodeWorld(World world, IEcsAdapter ecs, IComponentRegistry components)` — no `IRenderer`.

Entity lifecycle: `world.NativeSceneTree.CreateNode(name, parentEntity)` for creation; `world.NativeSceneTree.DestroyNode(entity)` for destruction.

Tracks managed Nodes:
- `_behaviors: List<Node>` — nodes that override `OnUpdate`
- `_labels: List<Label>` — managed label nodes
- `_byName: Dictionary<string, Node>` — lookup by name

Public API (mirror of legacy `Tree`):
- `AddNode<T>(T node, string name, Node? parent)` — binds node, creates native entity, calls `OnBind`
- `PreAddNode(Node, string, Node?)` / `CompleteAddNode(Node)` — two-phase bind used by SceneRouter
- `Find(string)` / `Find<T>(string)`
- `DestroyNode(Node)` — recursive, removes from `_behaviors`/`_labels`
- `Clear()` — flush all root nodes
- `Set<T>(ulong, T)` / `TryGet<T>(ulong, out T)` — via EcsAdapter + ComponentRegistry

**Update `Node.cs`**: rename `Tree? Tree` → `NodeWorld? NodeWorld` (or alias). All `Tree!.Set/TryGet` calls route through `NodeWorld`. `OnBind(Tree)` → `OnBind(NodeWorld)`.

**Update `SceneRenderModule.Configure`**: register `NodeWorld` instead of `Tree`:
```csharp
services.AddSingleton<NodeWorld>(sp =>
    new NodeWorld(
        sp.GetRequiredService<World>(),
        sp.GetRequiredService<IEcsAdapter>(),
        sp.GetRequiredService<IComponentRegistry>()));
```

**Update `LabelContributor`**: constructor takes `NodeWorld` instead of `Tree`.

**Update `SceneRenderModule.OnLoad`**: resolve `NodeWorld`, pass its `Behaviors` to `BehaviorSystem`.

**Validation**: `dotnet build` green. No functional change yet — existing behavior preserved.

---

##### G2 — NativeSceneLoader replaces Tomlyn SceneLoader + SceneRouter wired (atomic commit)

**What**: `SceneRouter` stops calling `Tomlyn SceneLoader` and instead uses `NativeSceneLoader` (already implemented in `src/csharp/KernelEngine.Framework/Scene/NativeSceneLoader.cs`).

**Script factory trampoline**: `NativeSceneLoader.RegisterScriptFactory(Func<ulong, string, bool>)` accepts a callback. The callback receives `(entity, typeName)`, looks up the `NodeTypeRegistry`, instantiates the `Node` via `ActivatorUtilities`, calls `NodeWorld.PreAddNode` then `CompleteAddNode`. The factory returns `true` on success.

**Update `SceneRouter`**:
```csharp
// OLD:
_loader.LoadInto(_tree, _services, path);

// NEW:
_nativeLoader.Load(path);  // ke_scene_loader->load fires script_factory per entity
```

The `NodeWorld` no longer has `PreAddNode`/`CompleteAddNode` called by the managed loader — the native C loader drives the lifecycle; the script factory trampoline is the only managed callback.

**Delete** `Toolkit/Scene/SceneLoader.cs` (Tomlyn version).  
**Remove** `<PackageReference Include="Tomlyn" .../>` from `KernelEngine.Toolkit.csproj`.

**Update `SceneRenderModule`** (or new dedicated module): register `NativeSceneLoader` singleton + call `RegisterScriptFactory` after DI resolution.

**Validation**: scene file with `type = "Camera"` (or any existing node type) loads without Tomlyn. Build + scene load green.

---

##### G3 — Pong becomes PongModule + paddle component (atomic commit)

**What**: Pong registers its own component + apply callback at startup; scene files migrate from `[entity.properties]` to `[entity.components.paddle]`.

**`PongModule : IRuntimeModule`** in `examples/csharp/games/pong/`:
```csharp
public sealed class PongModule : IRuntimeModule
{
    public string Name => "Pong";
    public void Configure(IServiceCollection services) { }
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var world = services.GetRequiredService<World>();
        var ecs   = services.GetRequiredService<IEcsAdapter>();
        // register ke_paddle_component
        // register apply callback via world.Native->register_component_apply(world.Native, cid, &ApplyPaddle)
        // register systems: PaddleControlSystem, BallSystem, ScoreSystem, etc.
    }
}
```

**`ke_paddle_component`** (C struct declared in the pong example — NOT in `components.h`, game-specific):
```c
typedef struct { float pos_x; float pos_y; uint32_t move_action; } ke_paddle_component;
```
Or equivalent managed struct if declared on the C# side.

**Apply callback**: `[UnmanagedCallersOnly]` static method reads `move_action` string entry from `ke_variant_table_entry[]`, looks it up in `InputActions`, stores the action ID.

**Migrate scene files** (`Main.scene`, `Paddle.scene`):
- `[entity.properties]` blocks → `[entity.components.paddle]` (for entities that have a paddle)
- Camera, AmbientLight, Scoreboard: map to their respective component blocks

**Update `Paddle.cs`**:
- Remove `public PongAction MoveAction { get; set; }` (was set by reflection)
- Add `OnBind(NodeWorld)` override: reads `ke_paddle_component` from ECS via `NodeWorld.TryGet<PaddleManagedComponent>(Entity, out var c)` and captures `c.MoveAction`

**Validation**: Pong runs visually identical to before. Paddles respond to input, scoring works.

---

##### G4 — Final cleanup (atomic commit)

- Rename `NativeSceneLoader` → `SceneLoader` (in Framework namespace — the "Native" prefix was temporary to coexist with the Tomlyn version, which is now gone).
- Grep for any remaining `Tomlyn` references — should be zero.
- Grep for any remaining `Tree` type references (not the abstract concept, the old concrete class) — should be zero.
- Verify `ModelExtensions` or any other place that accepted `IRenderer` from a tree-level caller no longer does so.
- Update XML doc comments on `NodeWorld`, `SceneRouter`, `FrameworkModule`, `SceneRenderModule`.

**Validation**: `dotnet build` + `dotnet test KernelEngine.slnx` green. Pong runs.

---

##### G-phase design decisions (locked before coding)

11. **NodeWorld does not expose IRenderer** — render is a module that adds its own systems + services to DI. The entity/scene layer (World, SceneTree, NodeWorld) has zero awareness of rendering.
12. **Entity creation always through NativeSceneTree** — `World.NativeSceneTree.CreateNode(name, parentEntity)` is the sole entry point for entity creation in the Toolkit layer. `IEcsAdapter.CreateEntity()` is not called from `NodeWorld` directly.
13. **Game programs are modules** — each game (Pong, etc.) implements `IRuntimeModule` and registers its own components (+ apply callbacks), systems, and node types in `OnLoad`. Initially manual; source gen is post-merge.
14. **Apply callback is game's responsibility** — `[entity.components.X]` in a scene file routes through the apply registry. The game registers the apply callback for its own component type. The engine never reflects on game types.
15. **`NativeSceneLoader` renamed `SceneLoader` at G4** — the "Native" prefix was a transitional name to coexist with the Tomlyn loader. Once the Tomlyn loader is deleted, the correct name is simply `SceneLoader`.
16. **`PongResources` does not exist in the new model** — it was legacy. Game state (ball position, score, etc.) lives as ECS components accessed through systems.

---

#### 17.6.6 Remaining tasks on this branch — merge to main

**G-phase status:**

| Sub-phase | Status | Commit |
|---|---|---|
| G1 — NodeWorld replaces Tree | ✅ Done | `d07caaa` |
| G2 — NativeSceneLoader replaces Tomlyn, trampoline wired | ✅ Done | `3956667` |
| G3 — Pong becomes `PongModule` + paddle component via `[entity.components.paddle]` | ✅ Done | (pre-existing) |
| G4 — Final cleanup (`NativeSceneLoader→SceneLoader`, grep Tomlyn/Tree, XML docs) | ✅ Done | pending commit |

**Merge checklist:**

- [ ] G3 + G4 committed and build green
- [ ] Visual validation: Pong renders and plays correctly (Pong is the only Toolkit validator; examples 01–16 are pre-Runtime-V2 and do not validate the new model)
- [ ] `dotnet test KernelEngine.slnx` green
- [ ] `ctest --preset win` ≥ 518/520 (2 pre-existing RuntimeSpike failures are acceptable)
- [ ] Merge PR to `main`

**Everything outside this branch** is documented and prioritized in [`docs/FrameworkArchitectureV2.md`](FrameworkArchitectureV2.md) — that is the scope of the next branch.
