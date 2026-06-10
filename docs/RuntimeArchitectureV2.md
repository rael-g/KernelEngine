# Runtime Architecture V2 — `ke_runtime` Contract Design

**Status**:
- §3 (C ABI contract) — **Accepted (2026-06-XX)** after R1 spike validation (commit `b58b21f`). Vtable shape, Module/System lifecycle, Phase enum, and `register_*` signatures are locked.
- §4–§14 — Locked at design level; impl details revisable per phase as R2+ surfaces new constraints. Open questions in §11 still apply.
**Audience**: Engine maintainer + future plugin authors (renderer / physics / audio / scripting).
**Companion doc**: [`RenderArchitectureV2.md`](RenderArchitectureV2.md).

---

## 1. Purpose

The engine is currently a **set of APIs without a brain**. The C kernel exposes contracts (`ke_render`, `ke_window`, `ke_input`, `ke_ecs`); the host (C# `Application.cs` or hand-rolled Lua main loop) wires everything together and drives the frame loop. This pushes the **orchestration responsibility back to every game**, which:

- Bloats `Application.cs` (already large, will grow with each plugin)
- Forces every binding language (Lua spike, future Rust binding) to re-implement the orchestration glue
- Makes the engine name (`KernelEngine`) inaccurate — a kernel has a scheduler; ours doesn't
- Couples module ordering / lifecycle / thread affinity to host code instead of declaring it in the engine

**This document defines `ke_runtime`** — a C-ABI contract for a scheduler-centric runtime. A runtime owns the simulation world, schedules systems with dependency ordering, dispatches work to a thread pool, and extracts a frame snapshot for the render thread. The host becomes a **declarative wiring layer**: it instantiates modules and starts the runtime. The runtime runs the game.

First implementation: **`KernelEngine.Runtime.Flecs`**, wrapping [flecs](https://github.com/SanderMertens/flecs) (C, MIT, single-header, mature, has built-in scheduler with parallel execution + dependency graph).

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

Each runtime impl exposes its own `_create()`:

```c
// In src/c/kernel/include/kernel_engine/runtime/flecs/runtime_flecs.h
KE_API ke_result ke_runtime_flecs_create(ke_allocator *alloc,
                                         const ke_runtime_flecs_params *params,
                                         ke_runtime **out_runtime);
```

Same pattern as `ke_render_bgfx_create()` etc.

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

## 8. What flecs gives us "for free"

We are not reimplementing an ECS. flecs provides:
- Archetype-based component storage (fast iteration)
- Queries with read/write annotations
- Built-in parallel scheduler with dependency graphs
- Phases and pipelines (we map our `KE_PHASE_*` onto flecs's `EcsOnLoad`/`EcsPreUpdate`/etc.)
- Observers (reactive systems on add/remove/change — useful for our framework's lifecycle hooks)
- Component metadata reflection (mirrors our `ke_component_field` mechanism — potentially superseding it)
- Modules as a first-class concept (`ecs_module_init`)

What we add **on top** of flecs (the wrapper):
- `ke_runtime` C ABI translation
- Bridging `ke_phase` ↔ flecs's phases
- Bridging `ke_component_access` ↔ flecs's query terms with read/write annotations
- Routing flecs's worker dispatch through our `ke_task_scheduler`
- Frame packet lifecycle integration

What we keep separate from flecs:
- The `ke_ecs` contract — flecs's storage implements it, but we keep the contract abstract so a custom-built ECS or `entt` can replace flecs if a game needs a different trade-off

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

### Phase R1 — flecs spike
Stand up `src/c/runtime/flecs/` with `ke_runtime_flecs_create()` that satisfies the vtable for the smallest possible scenario: register one module, register one system in Update, tick 10 times, shut down. Validates flecs builds in our vcpkg + CMake stack. No real engine integration.

### Phase R2 — `KernelEngine.Runtime.Flecs` C# binding
Generate bindings via ClangSharp. Implement `IRuntime` C# wrapper. Smoke test: same trivial scenario from C#.

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
- After R1: flecs is buildable. If not, swap to entt + custom scheduler (much more work, but possible).
- After R3: contract proves it can host a real frame. If shape is wrong, revise the doc and try again before going deeper.
- After R5: Pong runs end-to-end identical visually + behaviorally. Hard gate.

---

## 11. Open questions

1. **Module versioning** — should `ke_module_params` carry a version field for ABI evolution? V2 says yes; defer the actual checking to V3 hot-reload era.
2. **Resource ownership** — who owns the bytes behind `ke_resource_handle`? Runtime, or allocator passed in? Probably runtime, with allocator hint. Lock in during R1.
3. **Cross-runtime portability of modules** — if a Module is written against the ABI, does it work on flecs AND a hypothetical custom impl? Yes by design. **But**: modules using flecs-specific features (observers, prefabs, relationships) won't be portable. **Doctrine**: modules that need those features explicitly opt out of portability and document the dependency.
4. **Render world separation** — currently the doc says render is NOT a separate runtime (it's a pipeline consuming the snapshot). Bevy uses a separate "sub-app" world. Lock the simpler "pipeline-only" approach unless a real use case demands sub-app.
5. **`ke_ecs` improvements proposed in §2** — generations, hierarchical relations, multi-component queries — should land in `ke_ecs` contract (everyone benefits) or only in the flecs runtime (faster, less symmetric)? Probably contract, so the doctrine "kernel = building blocks" stays honest.
6. **Lua/scripting integration** — how does a Lua script declare a Module? Probably a builtin `LuaScriptModule` that the runtime registers; Lua scripts then register systems through that bridge. Deferred to post-R5.
7. **Variadic queries in the C# source generator** — `Query<T1, T2, T3, T4, ...>` is unbounded in arity. Approaches: (a) generate `Query<T1>` through `Query<T16>` overloads (closest to how Bevy 0.x handled it before const generics); (b) use C# `ITuple` + boxing (slow); (c) emit per-method-call specialized query types in the generator (most flexible, more codegen). Lock during R2 once the source generator stub exists.

---

## 12. Non-goals (explicit)

- **Hot module reload** — V3 concern. Modules load once at startup.
- **Distributed / networked runtime** — out of scope.
- **Runtime swappable mid-game** — pick `FlecsRuntime` or `CustomRuntime` at startup, stays for the session.
- **Replacing `ke_ecs` storage** — flecs impl provides ECS storage, but the contract stays neutral. No "flecs everywhere" assumption.

---

## 13. Alternatives considered

- **entt** (C++, header-only, no scheduler) — would force us to write the scheduler ourselves; flecs gives it free. Rejected.
- **Roll our own scheduler on top of current sparse-set ECS** — months of work to match flecs's maturity, no payoff. Rejected unless flecs proves a build/integration nightmare in R1.
- **Bevy ECS as inspiration only (build our own)** — same reason as above. Rejected.
- **Don't have a runtime at all; keep `Application.cs`** — that's the current state. The doc exists because that state has failed the simplicity test for a >1-binding engine.

---

## 14. Status & next actions

- [x] User reviews this doc
- [x] Lock the C ABI signatures (§3) — ratified after R1 validation
- [x] R1: flecs build spike (commit `b58b21f`, 1 session — minimal vtable subset, 5 integration tests green)
- [x] Companion doc: [`RenderArchitectureV2.md`](RenderArchitectureV2.md)
- [ ] **R2 — C# bindings via ClangSharp + minimal `IRuntime` wrapper + first managed integration test**
- [ ] **R3 — First real example consumer (`01_window_scene` ported to runtime)**
- [ ] **R4 — Render module shim wrapping the current `KernelEngine.Render.Bgfx`** (so any example can opt into runtime keeping the current renderer)
- [ ] **R5 — Pong migrated to runtime** (hard gate: identical visual + behavioral)
- [ ] **R6 — Examples 02-15 migrated incrementally**
- [ ] **R7 — `Application.cs` deletion** (after every consumer migrated)

**This doc is the contract.** §3 is locked; impl drift away from §3 is a bug in the impl, not in the doc.
