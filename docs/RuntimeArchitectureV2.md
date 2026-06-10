# Runtime Architecture V2 — `ke_runtime` Contract Design

**Status**:
- §3 (C ABI contract) — vtable shape, Module/System lifecycle, Phase enum locked.
- §4–§15 — Locked at design level.
- **Architectural shape (settled after R2 retrospective)**:
  - `ke_runtime` and `ke_ecs` are **separate, focused contracts** (interface segregation). Neither implies the other.
  - A single plugin CAN satisfy multiple contracts when the underlying technology pairs them naturally (composition). **`KernelEngine.Runtime.Flecs` satisfies BOTH `ke_runtime` AND `ke_ecs`** because flecs's storage and scheduler are tightly co-designed and benefit from sharing internal state. The C# DI registers the same instance under both interfaces; the consumer asking for `IRuntime` and the consumer asking for `IEcs` don't know they're the same object.
  - This pattern is the integrated model used by Bevy / Unity DOTS / UE5 Mass / flecs itself, which all couple scheduler + storage in the same impl for performance reasons documented in §8.
  - A future `KernelEngine.Runtime.Simple` (separate plugin, not built now) can be added for the case where a game wants ECS impl flexibility — it would consume an externally-provided `ke_ecs*`. Until that case surfaces, flecs is the only runtime we build.
- R1/R2 commits (`b58b21f`, `87001a0`, `e3fba2a`) validated the C ABI shape and the binding pattern. The work continues from there.
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

**Design principle — contracts are focused, implementations compose**: `ke_runtime` only declares scheduler/orchestration concerns. `ke_ecs` only declares storage/query concerns. Consumers depend on the narrowest contract they need (ISP — interface segregation). **Implementations are free to satisfy multiple contracts in one plugin** when the underlying tech pairs them — like flecs does. This isn't a doctrine violation; it's the standard "one class, multiple interfaces" pattern at the C ABI level. The consumer asking for `IRuntime` doesn't know — and shouldn't care — that the same instance also satisfies `IEcs`.

First implementation: **`KernelEngine.Runtime.Flecs`** — single plugin DLL satisfying both `ke_runtime` AND `ke_ecs`. Uses flecs's pipeline as the scheduler and flecs's world as the storage, sharing internal state. Algorithm and ergonomics inspired by Bevy (declared access sets + dep-graph + parallel waves + deferred commands + fixed timestep) — flecs already implements all of it; we wire the C ABI surface to it. Worker dispatch routed through `ke_task_scheduler` so the engine-wide enkiTS pool stays unified.

Future possibility (built when justified, not before): **`KernelEngine.Runtime.Simple`** — a small in-house scheduler that consumes an externally-provided `ke_ecs*`. Exists for the case where a game wants ECS impl flexibility (custom storage, non-flecs ECS via plugin). Not on the immediate roadmap.

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

The runtime-internal component that decides system execution order each tick. Schedules across the engine-wide thread pool (enkiTS — see §6).

The scheduler runs **phases** in fixed order:
- `Startup` (once)
- `PreUpdate` (every tick)
- `FixedUpdate` (0..N times per tick — fixed-dt physics step, "Fix Your Timestep" accumulator pattern)
- `Update` (every tick — variable dt)
- `PostUpdate` (every tick)
- `Extract` (every tick — copies sim state into the frame packet)
- `Shutdown` (once)

`FixedUpdate` runs at a deterministic timestep (default 1/60s) regardless of frame rate. The runtime accumulates real elapsed time and runs `FixedUpdate` 0, 1, or N times per `tick()` to catch up. Standard pattern across Unity / Godot / Bevy; mandatory for stable physics (Box2D `world->Step(fixed_dt)`).

Within a phase, systems run in parallel modulo their read/write conflicts. Between phases, all systems of the current phase complete before the next phase starts (phase barrier).

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

    void  *user_data;
    void (*execute)(ke_runtime *runtime, void *user_data, float dt);
} ke_system_params;
```

System functions are plain C function pointers — same `[UnmanagedCallersOnly]` bridge pattern we already use for script callbacks. The execute callback gets the runtime pointer (for `get_world` / `get_resource` queries) and a `dt`.

### 3.4 Factory

Each runtime impl exposes its own `_create()`. **The factory signature is impl-specific** because different runtimes have different construction needs. The vtable return type (`ke_runtime*`) is uniform; how you get there isn't.

**flecs (integrated runtime + ECS)**:

```c
// In src/c/kernel/include/kernel_engine/runtime/flecs/runtime_flecs.h
KE_API ke_result ke_runtime_flecs_create(
    ke_allocator                  *alloc,
    ke_task_scheduler             *task_scheduler,  // borrowed; the shared pool
    const ke_runtime_flecs_params *params,
    ke_runtime                   **out_runtime);

// The same plugin exposes the ECS view of the same instance:
KE_API ke_ecs * ke_runtime_flecs_get_ecs(ke_runtime *runtime);
```

flecs owns its storage internally — the caller doesn't supply a `ke_ecs*`. Consumers needing the ECS view query `ke_runtime_flecs_get_ecs(runtime)` (or in C#, ask DI for `IEcs` which resolves to the same instance the `IRuntime` resolution returned).

**Hypothetical future simple (decoupled runtime + external ECS)**:

```c
// In src/c/kernel/include/kernel_engine/runtime/simple/runtime_simple.h
KE_API ke_result ke_runtime_simple_create(
    ke_allocator                   *alloc,
    ke_ecs                         *ecs,            // borrowed; consumer provides
    ke_task_scheduler              *task_scheduler, // borrowed
    const ke_runtime_simple_params *params,
    ke_runtime                    **out_runtime);
```

A `simple` runtime accepts any `ke_ecs*` because it doesn't own storage. **Not built now**; documented here so the eventual contract is unambiguous.

**Common doctrine across all impls**: the runtime never destroys borrowed dependencies on shutdown. `task_scheduler` outlives every runtime that consumed it; same for any externally-provided `ke_ecs*`.

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

**Worker pool**: single shared `ke_task_scheduler` (enkiTS). The runtime tells flecs (or any other impl) to use this pool via `ecs_set_threads()` or equivalent.

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

## 8. Scheduler + threading doctrine — flecs 4 with enkiTS pool injection

### 8.1 Why flecs (not in-house from scratch)

flecs's scheduler is **co-designed with its archetype storage** and benefits from sharing internal state. Specifically:

- **Archetype-aware system scheduling** — flecs knows which archetypes each query touches; reorders execution within a wave to maximize cache reuse. A generic external scheduler with opaque access sets can't replicate this.
- **Query inference** — flecs query terms carry read/write annotations; the scheduler reads them to build the conflict graph. No second source of truth (no chance for an external `access_list` to drift from the actual query).
- **Mature parallel scheduler** — handles dep ordering, conflict detection, wave dispatch, deferred command queue, fixed timestep accumulator. We'd be writing all this from scratch and chasing flecs's bugs for years.
- **Bevy / Unity DOTS / UE5 Mass all integrate storage + scheduler** — for the reasons above. The integration is the win, not a compromise.

Because both `ke_runtime` and `ke_ecs` are valid concerns and flecs satisfies both natively, **the `KernelEngine.Runtime.Flecs` plugin satisfies both `ke_runtime` and `ke_ecs` contracts from a single shared instance** (§1, §3.4). This is interface segregation at the contract level (each interface focused) + composition at the impl level (one class implements multiple interfaces) — the standard pattern, applied to C ABI plugins.

### 8.2 Bevy-style ergonomics — the C# sugar layer (§3.5)

What Bevy gives Rust developers via type inference (`Query<&mut T, &U>` → write T, read U) we give C# developers via a Roslyn source generator (`Query<Mut<T>, U>` + the access list emitted automatically). The C ABI keeps the explicit `access_list` field because dynamic-language bindings (Lua, Python) can't infer. So:

- **C# game devs**: write Bevy-style systems, never see `access_list`
- **Lua / other dynamic bindings**: declare access explicitly through their respective sugar
- **C ABI**: explicit, always — it's the lowest common denominator surface

### 8.3 Pool unification — flecs 4 with `ecs_set_task_threads` + enkiTS

flecs 3.x manages its own internal worker pool with no public hook to inject a custom dispatcher. That would mean two parallel pools coexisting (flecs threads + our enkiTS pool), each idle during the other's work.

**flecs 4.x ships `ecs_set_task_threads()`** — a public API that injects a custom task dispatcher. The flecs pipeline still does all its scheduling magic (archetype awareness, conflict graph, wave selection), then **delegates parallel execution to whatever dispatcher we provide**. We wire that dispatcher to our `ke_task_scheduler*` (enkiTS-backed). Result: **single engine-wide pool**.

The composition story stays clean:
- `KernelEngine.Runtime.Flecs` satisfies `ke_runtime` + `ke_ecs` — flecs is good at both
- `KernelEngine.TaskScheduler.Enki` satisfies `ke_task_scheduler` — enkiTS is good at it
- Inside the flecs plugin, an internal bridge converts flecs's task-thread callbacks into `ke_task_scheduler` dispatches — pool unified without forcing flecs into the role of a generic task scheduler

**Why not make flecs implement `ke_task_scheduler` too?** flecs's worker pool is designed for system execution (needs a world, an iterator, a query). Forcing it to dispatch arbitrary work items (asset decode, PSO compile, audio mixing) would require an adapter that creates dummy worlds per dispatch — fighting flecs's design for the sake of a "one plugin satisfies everything" purity that isn't a goal. Composition allows multiple-interface impls; it doesn't *mandate* them when the underlying tech doesn't pair naturally. enkiTS exists, is mature, is already wrapped behind `ke_task_scheduler`. Keep it.

### 8.4 What runs where (the actual threading story)

```
ke.sim thread (the only thread driving the runtime)
│
├── runtime.tick() called once per frame
│    │
│    ├── flecs pipeline.run()
│    │    ├── computes wave structure (archetype-aware)
│    │    ├── for each wave: calls our task_thread dispatcher
│    │    │    └── enqueues N task entries on ke_task_scheduler (enkiTS)
│    │    └── enkiTS workers execute the systems in parallel
│    │
│    └── frame packet is ready for ke.render
│
└── (between ticks: asset loaders, PSO compile, audio mixing,
     and other engine work also dispatch to ke_task_scheduler — same pool)

ke.render thread
└── consumes frame packet, drives the renderer
```

One pool, used by everything. ke.sim doesn't manage threads; it tells flecs to tick, flecs delegates to the pool. Other engine subsystems use the pool directly.

### 8.5 References worth pillaging

- **Bevy ECS source** — `bevy_ecs/src/schedule/` modules. The algorithmic shape (dep graph + parallel waves + deferred commands) is the conceptual model we want flecs to implement on our behalf. Useful for understanding what flecs is doing internally and what to expect from the C# sugar layer.
- **flecs 4 docs** — `ecs_set_task_threads()` documentation, task-threads example. Required reading before wiring the bridge.
- **flecs 4 migration notes** — API changes from 3.2.x to 4.x. Most are renames; a few are semantic shifts. Walk through carefully when adapting our binding.
- **Stride Engine (C#)** — `SchedulerProcessor.cs` — analogue C# implementation of declared-access + dispatch. Less directly useful now that flecs handles the scheduling, but a good reference for the C# wrapper shape.
- **Sebastian Aaltonen's writeups** — high-level job system patterns. Background reading; doesn't affect the wiring directly.

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
Stood up `src/c/runtime/flecs/` with `ke_runtime_flecs_create()` wrapping flecs's pipeline. 5 integration tests proved the vtable shape (register_module + register_system + tick + destroy). **Outcome**: vtable shape validated. **Hidden cost surfaced**: flecs scheduler can't be decoupled from flecs storage; see §8.1 for the architectural finding that ended this path.

### Phase R2 — `KernelEngine.Runtime.Flecs` C# binding ✅ (commits `87001a0`, `e3fba2a`)
ClangSharp bindings + `FlecsRuntime` C# wrapper + 8 C# integration tests + `00_runtime_minimal` example (R3-A) opening a GLFW window driven by the runtime. **Outcome**: ABI crosses to managed cleanly; trampoline pattern works; host-driven frame loop with runtime tick works end-to-end.

### Phase R2.5 — flecs 4 upgrade + ke_ecs surface expansion + pool unification

Three intertwined pieces of work driven by the §8 doctrine settlement:

1. **Upgrade flecs 3.2.11 → 4.1.5 in `vcpkg.json`**. Walk the binding for breaking changes (mostly renames in 3→4; should be a contained morning).
2. **Wire `ecs_set_task_threads()` to dispatch through `ke_task_scheduler*`** — internal bridge in `runtime_flecs.c` that converts flecs task-thread callbacks into enkiTS task enqueues. The runtime factory takes a `ke_task_scheduler*` and installs the bridge during init. Pool unification lands.
3. **Expand `ke_ecs` contract** with multi-component query + filter (`With`/`Without`) APIs. Wire `ke_ecs_flecs_get_ecs(runtime)` (or equivalent getter) so the same plugin satisfies `ke_ecs` from the same flecs world. C# `FlecsRuntime` class implements both `IRuntime` and `IEcs`; DI registers the same instance under both interfaces (the composition pattern from §1).

All R1/R2 commits (`b58b21f`, `87001a0`, `e3fba2a`) stay; we evolve from there. Tests stay green throughout (small batches, one piece at a time). Estimated: 1.5-2 sessions total.

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
- After R2.5: flecs 4 builds + ke_ecs surface expanded + pool unified via `ecs_set_task_threads`. All R1/R2 integration tests stay green; new tests cover the multi-contract DI pattern (same instance under `IRuntime` and `IEcs`). Hard gate before R3.
- After R3: contract proves it can host a real frame with renderer + window. If shape is wrong, revise the doc and try again before going deeper.
- After R5: Pong runs end-to-end identical visually + behaviorally. Hard gate.

---

## 11. Open questions

1. **Module versioning** — should `ke_module_params` carry a version field for ABI evolution? V2 says yes; defer the actual checking to V3 hot-reload era.
2. **Resource ownership** — who owns the bytes behind `ke_resource_handle`? Runtime, or allocator passed in? Probably runtime, with allocator hint. Lock in during R1.
3. **Cross-runtime portability of modules** — if a Module is written against the ABI, does it work on any `ke_runtime` impl + any `ke_ecs` impl? Yes by design: modules only see the contract surface. **But**: modules using `ke_ecs_flecs`-specific features (observers, prefabs, relationships, rich query terms) won't run on sparse-set. **Doctrine**: modules that need those features explicitly require a richer `ke_ecs` impl in their dependency list (analogous to how a render module today requires `ke_render`); they don't pretend to be portable.
4. **Render world separation** — currently the doc says render is NOT a separate runtime (it's a pipeline consuming the snapshot). Bevy uses a separate "sub-app" world. Lock the simpler "pipeline-only" approach unless a real use case demands sub-app.
5. **`ke_ecs` improvements** — multi-component queries (`query<T1, T2>`), entity generations (stale-ID detection), basic filters (With/Without). Land in the `ke_ecs` contract so every impl (sparse-set, future flecs storage) exposes them uniformly. Sparse-set impl gets the minimum to support `ke_runtime_simple`; richer features ride on `ke_ecs_flecs` if/when it ships. **Decision**: land in contract, not impl-specific — doctrine "kernel = building blocks" stays honest.
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

- **In-house scheduler (`ke_runtime_simple`) instead of using flecs's** — write our own scheduler in C following the Bevy algorithm; consume any `ke_ecs*`. **Considered and deferred**: real engines (Bevy, Unity DOTS, UE5 Mass, flecs) all integrate scheduler + storage for archetype-aware optimization. We'd be reinventing flecs's mature scheduler and losing the integration benefit. May be revisited in M3+ if a game genuinely needs an ECS impl that flecs can't host. For now, `ke_runtime_flecs` covers everything we plan to ship.
- **Forcing flecs to satisfy `ke_task_scheduler` too** — would unify everything in one plugin. Rejected: flecs's worker pool is designed for ECS system dispatch (needs a world + iterator + query), not generic compute. Wrapping it for asset/PSO/audio work needs ugly adapter code (dummy worlds per dispatch). Composition allows multi-contract impls; it doesn't *force* them when the tech doesn't pair naturally. enkiTS stays as `ke_task_scheduler`.
- **Stay on flecs 3.2.11 with two coexisting pools** — works today (R1/R2 already do this implicitly). Rejected: pool unification is a real win for cache locality + tracing/profiling clarity, and flecs 4 makes it cheap (one API call).
- **entt** (C++, header-only, no scheduler) — would force us to write the scheduler ourselves AND lose flecs's relationships/observers/prefabs. Rejected.
- **Bevy ECS as a copy target** — Rust, doesn't transfer directly. The ergonomic concepts (§3.5 source generator, deferred commands, fixed timestep, SystemSet) are what we copy, not the code.
- **Don't have a runtime at all; keep `Application.cs`** — that's the current state. The doc exists because that state has failed the simplicity test for a >1-binding engine.
- **External job library besides enkiTS** (Intel TBB, Marl, NVIDIA Hwloc) — enkiTS is already in the engine, already wrapped, already mature. No reason to swap.

---

## 14. Status & next actions

- [x] User reviews this doc
- [x] Lock the C ABI vtable shape + Module/System lifecycle + Phase enum (§3)
- [x] R1: flecs build spike (commit `b58b21f`) — validated ABI shape, surfaced flecs storage/scheduler coupling
- [x] R2: C# bindings via ClangSharp + `FlecsRuntime` wrapper + 8 managed tests (commits `87001a0`, `e3fba2a`)
- [x] R2 extra: `00_runtime_minimal` example proving GLFW window + tick loop run end-to-end (commit `e3fba2a`)
- [x] Companion doc: [`RenderArchitectureV2.md`](RenderArchitectureV2.md)
- [x] §3.4 factory signature documented — impl-specific construction; flecs creates ECS internally, hypothetical simple consumes external
- [x] §8 settled — flecs 4 satisfies `ke_runtime` + `ke_ecs` via composition; `ecs_set_task_threads` injects enkiTS dispatcher; pool unified
- [ ] **R2.5 — flecs 4 upgrade + ke_ecs surface expansion + pool unification**: (a) bump `vcpkg.json` to flecs 4.1.5; adapt binding to 4.x API. (b) wire `ecs_set_task_threads` to dispatch through `ke_task_scheduler*`. (c) expand `ke_ecs` contract with multi-component query + filters; expose `ke_runtime_flecs_get_ecs(runtime)`; `FlecsRuntime` C# class implements both `IRuntime` and `IEcs`. All tests stay green.
- [ ] **R3 — First real example consumer (`01_window_scene` ported to runtime)**
- [ ] **R4 — Render module shim wrapping the current `KernelEngine.Render.Bgfx`** (so any example can opt into runtime keeping the current renderer)
- [ ] **R5 — Pong migrated to runtime** (hard gate: identical visual + behavioral)
- [ ] **R6 — Examples 02-15 migrated incrementally**
- [ ] **R7 — `Application.cs` deletion** (after every consumer migrated)

**This doc is the contract.** §3 vtable + Module/System/Phase shape are locked; the factory signature and §8 doctrine were revised after R2 retrospective and are now the current contract. Impl drift away from any locked section is a bug in the impl, not in the doc.
