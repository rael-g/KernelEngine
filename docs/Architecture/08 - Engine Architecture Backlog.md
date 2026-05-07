# 08 — Engine Architecture Backlog

> **Status**: In Progress — Phases A–E implemented; F–S planned across three audits (threading, ECS, infrastructure). Additional tracks added: testing, tooling, rendering, cleanup.
> **Context**: Started as a multithread hardening plan after validating the 3-thread model through examples.
> Expanded through successive audits into a comprehensive backlog covering every structural weakness
> identified in the engine. Organized into numbered Phases (A–S) for the threading/ECS/infrastructure
> work, and named Tracks for orthogonal concerns (testing, tooling, rendering, cleanup, architecture).

---

## 0. Engine Goals and Priority Strategy

### Goals

1. **Building blocks for engine construction.** The primary output is a set of well-designed APIs
   that allow correct and diverse implementations. A good API that supports a mediocre implementation
   is more valuable than a perfect implementation with a bad API. Implementations improve over time;
   API mistakes compound.

2. **Demo-driven development.** The engine must evolve fast enough to develop a real game. Time spent
   perfecting infrastructure is time not spent building the feature set a game needs. We move fast,
   ship examples, and refactor only when the base is broad enough to justify it.

3. **Godot-like scene/node paradigm in the Framework.** The kernel stays pure ECS — no notion of
   "scene" or "node" beyond ECS wrappers. The Framework layer builds the Godot-like abstraction on
   top: `Node`, `Scene`, composable `.scene` files, `.project` config. The editor (future) will
   manipulate those files; they remain human-editable without an editor.

4. **Debuggability is a prerequisite, not a luxury.** Without fast feedback on what is broken,
   every new feature risks silently inheriting threading bugs or rendering defects from previous
   work. Minimum viable observability must be in place before the fast-prototyping phase begins.

### Priority Tiers

Items are assigned to one of four tiers. Work proceeds top-down; lower tiers are not started
until the tier above is stable.

---

#### Tier 1 — Verify and Stabilize *(do now)*

The engine has implemented many rendering features (shadow maps, clustered lights, SSAO, bloom,
IBL, normal maps) that have **no runnable example to verify them**. Before adding anything new,
we need E2E coverage of what already exists and a stable, debuggable baseline.

**Reordered 2026-05-06**: debuggability is now the explicit ordering criterion. Each Tier 1
item must either remove a class of silent bug, surface a failure mode, or shorten the
diagnose-fix loop.

| Item | What | Status |
|------|------|--------|
| Examples 01–05 migration | Migrate to Phase E API (`IResourceFactory`, `ISceneWriter`, `IInputReader`) | ✅ Done |
| Phase H | Remove `ke_message_pipe` — decided, clean the debt | ✅ Done |
| Track Y.1 (DB-01) | bgfx fatal callback — capture native abort with file/line/code | ✅ Done (a409f95) |
| Track Y.7 (DB-07) | Synchronous log flush — no buffered messages lost on crash | ✅ Done (8197ec1) |
| Track Y.8 (DB-08) | Native SEH crash handler — convert `0x80000003` to readable error | ✅ Done (499c177) |
| Track Y.6 (DB-06) | Top-level exception handler in `Application.Run` | ✅ Done (499c177) |
| Track Y.9 (DB-09) | Startup lifecycle logging — last-printed-line identifies hang phase | ✅ Done (499c177) |
| Phase F | Structured shutdown — `join_timeout` + cancellation chain | ✅ Done (b556003 + 3fb4835 — `condition_variable::wait_for` eliminated the Linux stub) |
| **Track P (NEW) — Wave 1** | **Platform Abstraction Layer (`IDevPlatform`)** — extract dev-only OS APIs (thread name) into a swappable backend; eliminate all `#ifdef` from KeThread | ✅ Done (b03ab70 → dbad9e7 chain) |
| **Track Y.10 (NEW)** | **Bindings-drift detection in CI — fail build if `ke_*.h` changed but `Generated/*.cs` didn't** | 🔲 Planned (motivated by bug 1.25) |
| **Track W.4 (NEW)** | **Layer boundary cleanup — `src/cpp` plugins must expose only `_create()`** | 🔲 Planned (motivated by bug 1.26 — `EntryPointNotFoundException`; rule formalized in CLAUDE.md) |
| Track Y.2 (DB-02) | `LogErr` C++ helper — every silent `return KE_ERROR_*` becomes a logged failure | 🔲 Planned |
| Track Y.3 (DB-03) | Debug logging in bgfx init — shader path, file existence, createUniform results | 🔲 Planned |
| Track Y.4 (DB-04) | Symbolic `ke_result` names in `KernelException` | ⚠️ Partial (e519eda) |
| Track Y.5 (DB-05) | Audit `_ =` Result discards in Framework | 🔲 Planned |
| Examples 06–13 (Track Z) | Create examples for every implemented feature — these are the E2E tests | 🔲 Planned |
| Track U.1 | Wire `WindowConfig.vsync` — trivial, removes a papercut | 🔲 Planned |
| **Phase L (PROMOTED)** | **Read/write set enforcement — catch silent component-write violations in debug** | 🔲 Planned (was Tier 4) |

---

#### Tier 2 — Threading Hardening *(minimum viable)*

Just enough to stop threading bugs from leaking into new features. Not the full audit — only
the items that cause **silent corruption or guaranteed crashes** during normal gameplay code.

| Item | What |
|------|------|
| Phase I | Entity generations — stale refs are currently undetectable |
| Phase J | Deferred structural mutations — script destroying an entity during update crashes |
| Phase K | Node registry thread safety — real race condition with enkiTS workers |
| Phase G | enkiTS CLR thread attachment — managed ISystem on worker threads |
| **Phase N (PROMOTED)** | **Profiling, Chrome Trace / Tracy — required to debug threading issues without prints** |

Phases L (read/write enforcement) was promoted to Tier 1.
Phase M (frame arena) is deferred — performance, no correctness impact.

---

#### Tier 3 — Fast Prototyping Base *(build the game foundation)*

With a verified feature set and stable threading, move fast on game-development features.

| Item | What |
|------|------|
| Track W.2 | `.scene` / `.project` file format — Framework only, kernel unchanged |
| Godot-like scene composition | `SceneAsset`, `SceneNode`, composable prefab hierarchy |
| Examples 06–13 extras | Extend examples to demonstrate scene composition once format exists |

---

#### Tier 4 — Deferred *(after broad game-dev base)*

Revisit only when the engine can drive a complete game and the ROI of hardening is clear.

| Item | What |
|------|------|
| ~~Phase L~~ | *Promoted to Tier 1 — debuggability* |
| Phase M | Frame arena allocator, zero malloc on hot path |
| ~~Phase N~~ | *Promoted to Tier 2 — debuggability* |
| Phase O | ABI versioning strategy |
| Phase P | Multi-component ECS queries |
| Phase Q | Full asset system (`AssetHandle<T>`, ref counting, async) |
| Phase R | Error context (`ke_error_context` thread-local) |
| Phase S | Real plugin contract (`ke_plugin_register`, runtime discovery) |
| Track T.2 | Screenshot regression CI |
| Track W.1 | Codebase audit — orphaned files, wrong-domain code, CMakeLists cleanup |
| Track X | Rendering: depth prepass, KTX2, offline asset pipeline |

---

## 1. Problem Catalog

Each defect is classified by severity and type.

### 1.1 [CRITICAL] Game developer has direct access to the GPU renderer from ke.sim

`Application` exposes `app.Renderer` — the real bgfx-backed renderer — to `OnReady` and `OnUpdate`,
both of which run on ke.sim. Calls like `app.Renderer.CreateMesh()` or `app.Renderer.ClearColor()`
cross the thread boundary silently.

```csharp
// TODAY — runs on ke.sim, calls bgfx API directly. Undefined behavior.
app.OnReady = () => {
    var handle = app.Renderer.CreateMesh(verts, indices); // ← WRONG THREAD
    app.Renderer.ClearColor(0.1f, 0.1f, 0.1f, 1f);       // ← WRONG THREAD
};
```

There is no guard, no compile-time error, no runtime assertion. The only reason this works today
is accidental timing: during `OnReady`, ke.render happens to be idle. If a game dev calls
`CreateMesh` from `OnUpdate`, the race with ke.render's submission loop is live.

**Root cause**: `Application` has a single `Renderer` object shared across threads with no
ownership model.

---

### 1.2 [CRITICAL] Input state is a mutable object shared between ke.main and ke.sim

`Input` is written by ke.main (`Input.Update()`) and read by ke.sim (`Node.OnUpdate` → `input.IsKeyDown()`).
There is no synchronization between these accesses. The `MessagePipe` path adds one frame of lag
for pressed/released events but the `IsKeyDown` state is read directly from a shared array.

**Consequence**: game dev code that reads input from `OnUpdate` may see partial state (ke.main is
mid-update), causing frame-inconsistent input, dropped frames, or phantom key states.

---

### 1.3 [HIGH] `volatile bool _running` is not a safe shutdown primitive

`_running` is read and written from three threads. `volatile` in C# guarantees visibility ordering
but does not make compound read-modify-write operations atomic. More critically:

- There is no timeout on `simThread.Join()` or `renderThread.Join()`. If ke.sim blocks on
  `FrameSync.BeginWrite()` waiting for ke.render (which already crashed), the join hangs forever.
- Exception propagation is manual (`renderException`, `simException` fields) and can silently drop
  exceptions if a second exception happens before the first is rethrown.

---

### 1.4 [HIGH] enkiTS worker threads are logically ke.sim sub-tasks but treated as unknown threads

The wave scheduler dispatches ECS system updates to enkiTS worker threads. These workers are
sub-tasks of ke.sim and operate within a single frame boundary — but game-developer-authored
`ISystem` implementations that allocate, log, or call managed code from those workers are entering
C# from arbitrary native threads, which has implications for GC, exception handling, and thread
name visibility.

---

### 1.5 [MEDIUM] `ke_texture_handle` and `ke_mesh_handle` have no "none" sentinel

`normal_map = 0` was documented as "disabled" but `GetTextureIdx(0)` returned the valid default
texture, silently activating the TBN normal-map path for every material without a normal map.
This caused a rendering bug that took multiple debugging sessions to find because the error was
completely invisible at the API boundary.

The same pattern exists for any other optional handle that defaults to zero.

---

### 1.6 [MEDIUM] No compile-time or runtime enforcement of thread contracts

Functions that must run on specific threads carry only doc-comment annotations. There is nothing
that catches violations at compile time or in debug builds at runtime. Bugs resulting from
thread-contract violations produce silent incorrect behavior (wrong renders, race conditions)
rather than fast, loud failures.

---

### 1.7 [LOW] Dead code path — `GlfwWindow.cpp` fully implemented but never executed

`src/cpp/window/glfw/src/GlfwWindow.cpp` contains a complete, compiling window implementation
that is never used. The real factory (`window_glfw_factory.cpp`) uses `WindowCore` +
`GlfwWindowDevice`. The dead file misled debugging efforts and increases the maintenance surface.

---

### 1.8 [LOW] `ke_message_pipe` has no remaining purpose

The pipe was originally the cross-thread event bus for input events (ke.main → ke.sim). With Phase D
replacing that path via `InputSnapshot`, no engine-internal consumer remains. The pipe adds
`Pump()` call overhead every ke.main tick and a mental model cost (async, drain-based) with no
benefit. The Observer pattern (signals) is a better fit for game-level events and will be
implemented when a concrete use case demands it.

---

### 1.9 [CRITICAL] Entity IDs have no generation — stale references are undetectable

```c
typedef uint64_t ke_entity;  // simple incrementing integer
```

When an entity is destroyed and its slot reused, any `ke_entity` value still held elsewhere
(C# `Node` objects, component data referencing other entities, `HierarchyComponent` parent/child
fields) silently refers to the new, unrelated entity. There is no way to detect this at runtime.

The `Node` static registry `Dictionary<ulong, Node>` makes this especially dangerous: destroying
a node and creating a new one may return the old C# `Node` object for the new entity.

**Fix**: `ke_entity = { uint32_t id; uint32_t generation; }`. Every create increments generation
for that slot. Every access validates the stored generation against the current slot generation.

---

### 1.10 [CRITICAL] Structural ECS changes during iteration corrupt the registry

`Node.AddComponent`, `Node.RemoveComponent`, and `Scene.DestroyNode` can be called from
`Node.OnStart` or `Node.OnUpdate` — which execute inside `ke_script_component` callbacks,
themselves called from the ScriptSystem running inside a wave.

The ScriptSystem declares `reads = {script_cid}` but a script that adds or removes a component
performs an untracked structural write to the registry. The wave scheduler does not know this,
offers no protection, and the sparse-set backing arrays can reallocate under other workers
iterating the same arrays.

**Fix**: command buffer of deferred mutations. Scripts enqueue `{AddComponent, entity, cid, data}`
entries during execution. After all waves complete and before `end_write`, the command buffer
is drained and mutations applied atomically.

---

### 1.11 [CRITICAL] `Node` static registry is shared mutable state accessed from enkiTS workers

```csharp
// Node.cs
private static readonly Dictionary<ulong, Node> s_registry = new();
```

This dictionary is written by `Scene.AddNode`/`DestroyNode` (ke.sim setup phase) and read by
`[UnmanagedCallersOnly]` script callbacks (called from enkiTS workers during wave execution).
`Dictionary<K,V>` in .NET is not thread-safe for concurrent reads during writes. Any structural
change to the dictionary (node creation/destruction) concurrent with a script callback reading
it is a race condition.

**Fix**: replace with `ConcurrentDictionary`, or enforce that structural registry changes
only happen outside wave execution (during the deferred mutation drain in Phase J).

---

### 1.12 [HIGH] Component pointers returned by `ke_ecs_component_get` can silently dangle

```csharp
var c = TransformPtr;  // returns ke_transform_component*
c->Position = value;   // uses pointer
// ... later in same frame ...
registry.AddComponent<SomeComp>(anyEntity, cid);  // may realloc backing array
// c is now a dangling pointer — no crash, silent corruption
```

The sparse-set implementation uses `std::vector`-style arrays per component type. Any
`AddComponent` call that exceeds current capacity triggers reallocation, invalidating all
pointers previously returned by `GetComponent` for that type. In a single-threaded world this
is a use-after-realloc. In the multithreaded world it is a data race.

**Fix** (short-term): assert in debug that component array capacity does not change between
`GetComponent` and its last use within a system's update. Document the contract explicitly.
**Fix** (long-term, Phase O): chunk allocators — fixed-size blocks, no realloc, stable pointers.

---

### 1.13 [HIGH] Wave scheduler trusts read/write set declarations without verification

The scheduler correctly parallelizes systems that declare non-conflicting access sets and
serializes conflicting ones. But it has no mechanism to verify that a system's actual runtime
behavior matches its declared sets. A system that declares `reads = {transform}` but in practice
writes to `transform` (e.g., via a script that modifies the TransformComponent) passes the
scheduler without any warning and creates a silent race with other systems reading the same
component in the same wave.

**Fix**: in debug builds, the scheduler wraps each component array access with a guard that
records which system is currently writing or reading. Any access that violates the declared
sets triggers an immediate assertion.

---

### 1.14 [HIGH] Frame packet uses pre-allocated capacities with no overflow protection beyond a counter

`draw_capacity = 2048` is set at `FrameSync` creation. If more than 2048 draw commands are
submitted in a frame, `atomic_fetch_add` on `draw_count` will exceed `draw_capacity` and
systems will write past the end of the `draw_commands` array — classic buffer overflow, no
bounds check, no error return to the caller.

Additionally, any future dynamic array inside the packet (e.g., per-frame string labels for
profiling) risks heap allocation on the hot path, causing frame spikes.

**Fix**: bounds check in every recording path (`if (index >= draw_capacity) return`). Long-term:
frame arena allocator — linear bump allocator reset at `begin_write`, all per-frame allocations
drawn from it, zero `malloc` on the hot path, deterministic frame time.

---

### 1.15 [HIGH] No profiling or thread timeline observability

Three named threads, enkiTS workers, wave barriers, frame handoff — none of this is visible to
any profiler. When a frame spike occurs or a wave takes longer than expected, diagnosis is
guesswork. `printf` debugging multithreaded systems is not a strategy.

**Fix**: a minimal scope-based profiler with per-thread ring buffer, flushed to a Chrome
Trace JSON (`chrome://tracing`) or Tracy integration. Scopes cost one `rdtsc` + one atomic
write — negligible in release, priceless in debug.

---

### 1.22 [CRITICAL] `ke_system_desc` carries `ke_render*` — enables GPU calls from ke.sim

The `ShadowSystem` context stores a `ke_render*` pointer passed at construction time.
Inside `ShadowSystem::Update` (called by ke.sim via `World.Update`), this pointer was used to
call `ctx->renderer->create_shadow_map` — a bgfx GPU operation that **requires ke.render**.

`ke_thread_assert_current("ke.render")` inside `bgfx_gpu_device.cpp` caught this and called
`abort()`, producing the thread affinity violation crash.

The architectural problem is that the type system allows it. A `ke_system_desc` with a
`ke_render*` in its handle is a loaded gun: any system can call GPU functions from ke.sim
and the only protection is a runtime assertion that fires as a hard crash with no stack trace.

**Fix**: systems must never receive a renderer pointer. The ECS system contract is:
- Input: `ke_world*` (ECS queries) + `ke_frame_packet*` (write slot)
- Output: entries written into the frame packet
- Never: renderer calls, GPU resource creation, threading primitives

Any GPU resource a system needs (shadow map handle, built-in textures, program handles) must be
pre-created on ke.render and injected into the system context as opaque handle values — not as
a live renderer pointer.

Remove `ke_render*` from `ShadowSystem::GetDescription` and any future system descriptors.
Add a `ke_render_bgfx_shadow_system_set_map(desc, handle)` setter pattern as the only approved
injection point, callable only from ke.render after GPU init.

---

### 1.23 [HIGH] No formal "setup phase" — `ResourceCommandQueue` drain deadlocks during `OnReady`

The three-thread model has an implicit phase between ke.render initialization and the first
frame that has no architectural support:

```
ke.render:  Initialize() → [enters BeginRead — blocks waiting for first frame]
ke.sim:     OnReady() → CreateMaterial() → [blocks waiting for ke.render to drain queue]
```

This is a deadlock. ke.render is waiting for a frame; ke.sim can't produce a frame until its
`OnReady` resource creation completes; ke.render can't drain the resource queue because it
already entered `BeginRead`.

**Workaround in place**: a `simReady` `ManualResetEventSlim` was added. ke.render
spin-drains the `ResourceCommandQueue` via `Thread.SpinWait(100)` until ke.sim signals
that `OnReady` is complete, then enters the frame loop. This works but is polling-based.

**Proper fix**: replace the spin-drain with ke.render's main loop calling
`WaitHandle.WaitAny(new[] { resourceQueueSemaphore, frameAvailableSemaphore })` — ke.render
sleeps on whichever event fires first. The resource queue semaphore is signaled by `Enqueue`;
the frame semaphore is signaled by `EndWrite`. This eliminates both the spin-wait and the
need for the `simReady` event entirely.

This requires `FrameSync.BeginRead` to expose its internal semaphore (or a combined wait
primitive), and `ResourceCommandQueue.Enqueue` to signal a semaphore.

---

### 1.24 [MEDIUM] `KeThread` captured thread name as pointer — use-after-free on startup

In `KernelThread.Create`, the thread name was allocated with `Marshal.AllocHGlobal`, passed to
`ke_thread_std_create` via a `ke_thread_desc*`, and freed in the `finally` block — before the
new thread's body executed `set_thread_name_platform(desc_copy.name)`.

The `KeThread` constructor captured `desc_copy = *desc` (a shallow struct copy), so
`desc_copy.name` was a dangling pointer by the time the thread body ran. The thread name would
be set to garbage, making `ke_thread_assert_current` fire false positives.

**Fix applied**: `KeThread.cpp` now captures `name = std::string(desc->name ? desc->name : "")` in
the lambda — a deep copy that outlives the caller's allocation lifetime.

**Class of bug**: any function in the codebase that passes a `const char*` to a cross-thread
consumer (thread body, callback, async queue) without ensuring the string outlives the consumer
is vulnerable to this pattern. Audit: `ke_system_desc::name`, `ke_logger_sink::name`, any
struct with a `const char*` that is stored for later use.

---

### 1.16 [LOW] Resource creation is blocking and synchronous with no async alternative

`CreateMesh`, `CreateTexture`, `CreateCubemap` called from `OnReady` block ke.sim until ke.render
processes them (currently not even queued — they go directly to bgfx on the wrong thread). There
is no path for background asset loading during gameplay.

---

### 1.17 [CRITICAL] C kernel has no ABI versioning strategy

The kernel C API is intended to be the stable contract between the kernel, plugins (bgfx, GLFW),
and the C# P/Invoke layer. But there is no version number, no struct size validation, and no
policy governing what changes are allowed between releases.

Adding a field to `ke_transform_component` (required by Phase I for entity generations) will
silently shift all subsequent fields in every plugin compiled against the old header. The binary
continues to link. The crash or corruption occurs at runtime, during data access, and is
extremely difficult to trace back to a struct layout mismatch.

Without ABI stability guarantees, the "microkernel with swappable plugins" promise is
structurally hollow — any change to the kernel breaks all plugins.

---

### 1.18 [HIGH] ECS only supports single-component queries — multi-component access is O(n) per entity

The current query API returns entities and data for one component type:

```c
ke_ecs_registry_query(reg, transform_cid, &entities, &data, &count);
```

Any system that needs two or more components (e.g., `TransformComponent + MeshComponent`) must
call `ke_ecs_component_get(entity, other_cid)` per entity inside the loop — a pointer lookup
per entity, per extra component, defeating cache locality. This is the dominant performance
bottleneck for systems with complex queries as scene complexity grows.

---

### 1.19 [HIGH] No asset system — resource lifetime is unmanaged and ad-hoc

GPU resources (`MeshHandle`, `TextureHandle`, `MaterialHandle`) are created in `OnReady` and
never formally tracked. There is no reference counting, no streaming, no hot reload, and no
guaranteed destruction order at shutdown. As scenes grow, this becomes:

- Memory leaks when handles are lost without explicit `Destroy` calls.
- No way to share assets between nodes (each node creates its own copy).
- No path for background loading of large assets during gameplay without blocking ke.sim.
- No way to reload a shader or texture without restarting the application.

The `IResourceFactory` introduced in Phase E is the creation layer. The asset lifecycle
management layer does not exist.

---

### 1.20 [MEDIUM] `ke_result` loses all diagnostic context by the time it reaches the caller

```c
ke_result res = ke_ecs_component_add(reg, entity, cid, data);
if (res != KE_OK) return res;  // which entity? which cid? what data? unknown.
```

`ke_result` is a bare enum. When an error propagates through three call layers, the original
context — which argument was invalid, what value caused the failure, which internal invariant
was violated — is gone. In development builds this forces printf-debugging every error site.
In a plugin compiled by a third party, it makes failures nearly undiagnosable.

---

### 1.21 [MEDIUM] Plugin loading is not a real contract — backends are compile-time dependencies

bgfx and GLFW are documented as "plugins" but are loaded via direct DLL imports resolved at
process startup. There is no runtime discovery, no version negotiation, and no capability
query. Swapping the renderer backend (e.g., bgfx → WebGPU) requires modifying the C# framework
layer and recompiling. A third party cannot write a renderer plugin without forking the engine.

A real plugin contract would expose a single well-known exported symbol per DLL
(`ke_plugin_register`) that the kernel calls at load time to negotiate capabilities and wire
vtable slots. The plugin would declare what it provides; the kernel would validate compatibility.

---

## 2. Target Architecture

### 2.1 Thread Ownership Model

```
ke.main   — owns: Window (GLFW), OS event loop
             reads: nothing shared
             writes: InputSnapshot (lock-free producer)

ke.render — owns: all bgfx API calls, ResourceCommandQueue consumer
             reads: ke_frame_packet (via FrameSync)
             writes: resource handles (via ResourceFuture)

ke.sim    — owns: World.Update, ECS System Graph, game logic
  └── enkiTS workers — own: individual ECS system wave tasks
             reads: InputSnapshot (lock-free consumer), ECS components
             writes: ke_frame_packet (via FrameSync, atomic draw_count)
```

**The invariant**: a thread owns what it reads AND writes. Crossing ownership requires an
explicit, typed boundary (FrameSync, ResourceCommandQueue, InputBuffer). There is no shared
mutable object accessible from two threads without a boundary.

---

### 2.2 The Sim-Side Renderer: `ISceneWriter`

The game developer never receives a `Renderer`. Instead, they receive two objects:

**`ISceneWriter`** — available in `OnUpdate`. Writes only into the current `ke_frame_packet`.
No GPU calls. No bgfx. Cannot be misused to call the wrong thread.

```csharp
public interface ISceneWriter
{
    void ClearColor(float r, float g, float b, float a);
    void SetAmbientLight(float r, float g, float b);
    void SetDirectionalLight(Vector3 direction, Vector3 color, float intensity);
}
```

`ISceneWriter` is implemented by a thin wrapper that holds a pointer to the current
`ke_frame_packet` write slot. It is created fresh each frame by `Application` and passed
into `OnUpdate`. It cannot outlive the frame — the packet's `EndWrite` invalidates it.

**`IResourceFactory`** — available in `OnReady` and at any time during `OnUpdate`.
Sends resource creation commands to ke.render via the `ResourceCommandQueue` and returns
typed, immutable handles.

```csharp
public interface IResourceFactory
{
    MeshHandle   CreateMesh(ReadOnlySpan<ke_vertex> vertices, ReadOnlySpan<ushort> indices);
    TextureHandle CreateTexture(int width, int height, ReadOnlySpan<byte> rgba);
    CubemapHandle CreateCubemap(int faceSize, ReadOnlySpan<byte> faceData);
    MaterialHandle CreateMaterial(MaterialDesc desc);

    void DestroyMesh(MeshHandle handle);
    void DestroyTexture(TextureHandle handle);
    // ...
}
```

`CreateMesh` enqueues a command to ke.render and blocks ke.sim until ke.render returns the
handle. This is intentionally synchronous for `OnReady`. For `OnUpdate`, async variants
return a `ResourceFuture<T>` that resolves next frame.

---

### 2.3 Typed, Safe Resource Handles

Replace all `uint32_t` handles with distinct types that carry their "none" semantics explicitly.

**C API:**

```c
// Before
typedef uint32_t ke_mesh_handle;
#define KE_MESH_HANDLE_INVALID ((ke_mesh_handle)UINT32_MAX)

typedef uint32_t ke_texture_handle;  // 0 = "none" per comment — inconsistent and wrong

// After
typedef struct { uint32_t idx; } ke_mesh_handle;
typedef struct { uint32_t idx; } ke_texture_handle;
typedef struct { uint32_t idx; } ke_material_handle;
typedef struct { uint32_t idx; } ke_cubemap_handle;

#define KE_HANDLE_NONE UINT32_MAX
#define KE_MESH_NONE     ((ke_mesh_handle){KE_HANDLE_NONE})
#define KE_TEXTURE_NONE  ((ke_texture_handle){KE_HANDLE_NONE})
// ...

static inline bool ke_mesh_is_valid(ke_mesh_handle h)    { return h.idx != KE_HANDLE_NONE; }
static inline bool ke_texture_is_valid(ke_texture_handle h) { return h.idx != KE_HANDLE_NONE; }
```

The struct wrapper makes mixing `ke_mesh_handle` with `ke_texture_handle` a compile error in C.
The `KE_HANDLE_NONE = UINT32_MAX` sentinel is explicit everywhere — `0` is always a valid handle.

**C# side:**

```csharp
// Strongly typed, no accidental interop between handle types
public readonly record struct MeshHandle(uint Value)
{
    public static readonly MeshHandle None = new(uint.MaxValue);
    public bool IsValid => Value != uint.MaxValue;
}
```

---

### 2.4 Input as Frame Snapshot

Remove `Input` from ke.sim's direct reach. ke.main produces an `InputSnapshot` every frame;
ke.sim consumes it atomically at the start of each `World.Update`.

**C struct (added to `ke_frame_packet`):**

```c
typedef struct ke_input_snapshot {
    uint8_t down[512];     // 1 if key is held
    uint8_t pressed[512];  // 1 if key went down this frame
    uint8_t released[512]; // 1 if key went up this frame
} ke_input_snapshot;
```

The snapshot is written by ke.main into a dedicated single-element exchange buffer
(`InputBuffer`, not the FrameSync ring), then read at the top of each ke.sim frame.
The exchange is a single atomic pointer swap — no lock, no lag beyond one ke.main tick.

**Game developer API (unchanged in feel, different in implementation):**

```csharp
// OnUpdate receives the snapshot, not the live Input object
app.OnUpdate = (ISceneWriter scene, IInputReader input) => {
    if (input.IsKeyDown(Key.W)) ...  // reads from snapshot — perfectly safe
};
```

`IInputReader` is a thin wrapper over `ke_input_snapshot`. It is read-only. It has no
connection to ke.main's live state.

---

### 2.5 Structured Shutdown

Replace `volatile bool _running` with a `CancellationTokenSource` and add timeouts.

```csharp
using var cts = new CancellationTokenSource();

// Shutdown trigger — can come from any thread
void RequestStop() => cts.Cancel();

// ke.main loop
while (!cts.IsCancellationRequested)
{
    Window.PollEvents();
    if (Window.ShouldClose()) RequestStop();
    Input.Update();
    MessagePipe?.Pump();
}

// Shutdown sequence — guaranteed to not hang
cts.Cancel();
if (!simThread.Join(TimeSpan.FromSeconds(5)))
    Logger?.Error("Application", "ke.sim did not stop within 5s — forcing exit");
if (!renderThread.Join(TimeSpan.FromSeconds(3)))
    Logger?.Error("Application", "ke.render did not stop within 3s — forcing exit");
```

Exception propagation is replaced with `ExceptionDispatchInfo` captured per-thread and
rethrown on ke.main after joins, preserving the original stack trace.

---

### 2.6 Thread Affinity Enforcement

A lightweight attribute + debug-mode assertion catches cross-thread violations immediately
rather than silently.

**C# (debug mode):**

```csharp
[AttributeUsage(AttributeTargets.Method)]
public sealed class RequiresThreadAttribute(string threadName) : Attribute { }

// Applied to any renderer internal method
[RequiresThread("ke.render")]
internal void SubmitPacketInternal(ke_frame_packet* packet) { ... }

// Runtime check in debug builds
[Conditional("DEBUG")]
public static void AssertThread(string name)
{
    if (Thread.CurrentThread.Name != name)
        throw new ThreadAffinityViolationException(
            $"Expected thread '{name}', running on '{Thread.CurrentThread.Name}'");
}
```

**C/C++ (debug mode):**

```c
#ifdef KE_DEBUG
  #define KE_ASSERT_THREAD(name)  ke_assert_current_thread(name)
#else
  #define KE_ASSERT_THREAD(name)  ((void)0)
#endif
```

Placed at the entry of every bgfx-calling function in `frame_submitter.cpp`. Violations
become immediate crashes with a clear message in debug builds and zero cost in release.

---

### 2.7 Resource Command Queue

Enables safe resource creation from ke.sim without crossing the thread boundary.

```
ke.sim                    ResourceCommandQueue              ke.render
  │                              │                              │
  │── CreateMesh(verts) ────────►│                              │
  │   (enqueues, blocks)         │── drain queue (per frame) ──►│
  │                              │                              │── bgfx::createVertexBuffer
  │◄── MeshHandle(42) ──────────◄│◄─────────────────────────────│
  │   (unblocks)                 │                              │
```

The queue is a lock-free MPSC ring (single consumer = ke.render). Each entry is a tagged
union of resource creation commands. ke.render drains it at the start of each frame, before
processing the `ke_frame_packet`. Completion is signaled via a per-command `std::promise`
(C++) or `SemaphoreSlim` (C#).

For async creation (during gameplay), `CreateMeshAsync()` returns a `ResourceFuture<MeshHandle>`
that resolves on the next ke.render frame without blocking ke.sim.

---

### 2.8 enkiTS Worker Thread Clarity

The enkiTS worker pool is a sub-executor of ke.sim. Workers exist only to parallelize
ECS system waves within a single frame. They are not a fourth thread category.

**Clarified contracts:**

- enkiTS workers run during `World.Update()` on ke.sim's frame tick.
- Workers may only access data that the wave scheduler has granted (component arrays, frame_packet write slots).
- Workers must never call ke.render APIs, touch the ResourceCommandQueue as consumers, or access ke.main state.
- C# `ISystem.Update()` called from a worker thread is supported. Managed code on unmanaged threads requires the CLR to have attached the thread — `KernelThread.Create` must call `Thread.BeginThreadAffinity()` for workers.
- The System Graph scheduler already enforces read/write dependency rules. No additional synchronization is needed within a wave.

---

### 2.10 Formal Setup Phase

The current `Application.Run()` uses a `simReady` `ManualResetEventSlim` and a spin-drain
loop (`Thread.SpinWait(100)`) to synchronize `OnReady` resource creation with ke.render.
This is a workaround, not a design.

**Proper design**: `ResourceCommandQueue.Enqueue` should expose a semaphore that ke.render
waits on (alongside the `FrameSync` semaphore) in `WaitHandle.WaitAny`. ke.render wakes
up when *either* a resource command arrives or a frame is available, handles whichever is
ready, then sleeps again. This makes the setup phase and the frame loop unified — no special
pre-loop drain, no `simReady` event, no spin-waiting.

```csharp
// ke.render main loop (target shape):
while (!_cts.IsCancellationRequested)
{
    var idx = WaitHandle.WaitAny(new[] { resourceSemaphore, frameSemaphore, cancelHandle });
    if (idx == 0) { _resourceQueue.Drain(Renderer); continue; }
    if (idx == 1) { var p = frameSync.BeginRead(); Renderer.SubmitPacket(p); Renderer.Frame(); p.EndRead(); }
}
```

**Prerequisite**: `ResourceCommandQueue` must expose its internal semaphore, and `FrameSync`
must expose its reader semaphore, so `Application` can compose them with `WaitHandle.WaitAny`.

**Tracked in**: problem 1.23.

---

### 2.9 Remove Dead Code

`src/cpp/window/glfw/src/GlfwWindow.cpp` and any other unreferenced implementation files
must be deleted. The CMake target must not compile them. Dead code that compiles but does
not link is not dead — it is a trap.

Rule going forward: if a `.cpp` file is not referenced in a `CMakeLists.txt` `target_sources`,
it must be deleted, not archived.

---

## 3. Refactoring Phases

Each phase is independently shippable. Examples must compile and run correctly at the end
of each phase.

### Phase A — Handle Safety (prerequisite for everything else)

**Goal**: eliminate the class of bugs where `handle = 0` means both "valid handle" and "none".

1. Define `ke_handle_none = UINT32_MAX` in `math.h` or a new `handles.h`.
2. Add `ke_*_is_valid()` inline helpers for all handle types.
3. Add struct wrappers for C handle types (optional for C, required for C++ callers).
4. Update `frame_submitter.cpp`: all optional handle checks use `ke_texture_is_valid()`.
5. Update C# handle types to `readonly record struct` with `.None` and `.IsValid`.
6. Audit all material fields (`normal_map`, `albedo`) — ensure consistent sentinel usage.

**Validation**: the normal-map bug class cannot reoccur. Passing a zero handle where no
texture is intended must produce "use default" behavior, not "use texture at slot 0".

---

### Phase B — Dead Code Removal

**Goal**: eliminate all unreachable code paths from the build.

1. Delete `src/cpp/window/glfw/src/GlfwWindow.cpp`.
2. Verify `GlfwWindow.hpp` is not referenced externally; delete if so.
3. Grep for any `#include "GlfwWindow"` references — remove.
4. Rebuild + run all tests.

---

### Phase C — Thread Affinity Enforcement

**Goal**: violations of thread contracts crash loudly in debug builds.

1. Implement `KernelThread.AssertCurrent(string name)` in C#.
2. Implement `ke_assert_current_thread()` in C/C++.
3. Add assertions to all bgfx-calling functions in `frame_submitter.cpp` and `BgfxGpuDevice`.
4. Add `[RequiresThread("ke.render")]` attribute to internal Renderer methods.
5. Add assertions to `Input.Update()` (must be ke.main) and `World.Update()` (must be ke.sim).

**Validation**: calling `Renderer.SubmitPacket` from ke.sim crashes with a clear message.

---

### Phase D — Input Snapshot

**Goal**: ke.sim reads a frozen, consistent view of input state with no shared mutable state.

1. Define `ke_input_snapshot` in a new `input_snapshot.h`.
2. Implement `InputBuffer` — a C# lock-free single-slot exchange (one producer, one consumer).
3. ke.main: after `Input.Update()`, snapshot state into `InputBuffer.Produce()`.
4. ke.sim: at the start of each `World.Update()`, consume the snapshot.
5. `IInputReader` interface wraps the snapshot — replaces `Input` in game-developer API.
6. Update `Application.OnUpdate` signature: `Action<ISceneWriter, IInputReader>`.
7. Update all examples to use `IInputReader` instead of `app.Input`.

**Validation**: removing `app.Input` from public `Application` API causes compile errors in
code that bypassed the snapshot. All examples still function.

---

### Phase E — ISceneWriter and IResourceFactory

**Goal**: game developer never touches `Renderer` directly. All GPU work is mediated.

1. Define `ISceneWriter` with the frame-level commands (`ClearColor`, `SetAmbientLight`, etc.).
2. Implement `FramePacketSceneWriter` — wraps `ke_frame_packet*`, asserts ke.sim thread.
3. Define `IResourceFactory` with typed creation/destruction methods.
4. Implement `ResourceCommandQueue` — lock-free MPSC queue drained by ke.render each frame.
5. Implement `ResourceCommandFactory` — enqueues and blocks with `SemaphoreSlim`.
6. Update `Application.OnReady` signature: `Action<IResourceFactory>`.
7. Update `Application.OnUpdate` signature: `Action<ISceneWriter, IInputReader>`.
8. Remove `app.Renderer` from public `Application` API.
9. Update all examples.

**Validation**: after this phase, it is architecturally impossible for game code to call bgfx
from the wrong thread. The compiler enforces it.

---

### Phase F — Structured Shutdown

**Goal**: the engine always shuts down cleanly, even if a thread crashes.

1. Replace `volatile bool _running` with `CancellationTokenSource`.
2. Add `Join(TimeSpan timeout)` with logging on timeout.
3. Replace manual exception fields with `ExceptionDispatchInfo` captured in thread lambdas.
4. Add ke.render's ResourceCommandQueue drain to the shutdown sequence (flush pending creates).
5. Test: kill ke.render artificially — ke.sim must unblock and exit within timeout.

---

### Phase G — enkiTS Managed Thread Safety (planned)

**Goal**: C# `ISystem` implementations called from enkiTS workers work correctly under the CLR.

1. Audit `KernelThread.Create` — verify CLR thread attachment for worker threads.
2. Add `[ThreadSafe]` documentation attribute to `ISystem.Update` — clarify expected contract.
3. Verify `EcsRegistry` read-only query path (`ke_ecs_component_get`) is reentrant.
4. Add debug assertions inside `ISystem.Update` dispatch that verify the calling thread is a
   known ke.sim worker.

---

### Phase H — Remove `ke_message_pipe`

**Goal**: eliminate the cross-thread event bus that has no remaining consumers.

1. Remove `ke_message_pipe` from `ke_window_glfw_params` (already wire-removed by Phase D).
2. Remove `MessagePipe` from `Application` DI setup and public API.
3. Delete `src/c/kernel/include/kernel_engine/kernel/messaging/` and implementation.
4. Remove `AddMessagePipe()` extension method from all service collections.
5. Update all examples to remove `.AddMessagePipe()`.
6. Delete `ke_msg_key_event` and `input_messages.h` (superseded by `ke_input_snapshot`).

**Validation**: grep for `message_pipe`, `ke_message_pipe`, `MessagePipe` — zero results outside
test history and git log.

---

### Phase I — Entity Generations

**Goal**: stale entity references become detectable errors, not silent corruption.

**C kernel changes:**

```c
// Before
typedef uint64_t ke_entity;
#define KE_ENTITY_INVALID UINT64_MAX

// After
typedef struct {
    uint32_t id;
    uint32_t generation;
} ke_entity;
#define KE_ENTITY_INVALID ((ke_entity){UINT32_MAX, 0})

static inline bool ke_entity_is_valid(ke_entity e) { return e.id != UINT32_MAX; }
static inline bool ke_entity_equal(ke_entity a, ke_entity b) {
    return a.id == b.id && a.generation == b.generation;
}
```

The ECS registry maintains a `uint32_t generation[MAX_ENTITIES]` table. On destroy, the slot's
generation is incremented. On `ke_ecs_component_get(entity)`, if the stored generation for
`entity.id` does not match `entity.generation`, return `NULL` (debug: assert-fail).

**Steps:**
1. Add `generation` table to `ke_ecs_registry` implementation.
2. `ke_world_create_node` sets generation from table on entity creation.
3. `ke_world_destroy_node` increments generation for the slot.
4. All `ke_ecs_component_get` / `ke_ecs_component_add` paths validate generation.
5. Update `HierarchyComponent` parent/child/sibling fields to `ke_entity` struct.
6. Update C# `ke_entity` binding to a `[StructLayout(LayoutKind.Sequential)]` struct with
   `Id` and `Generation` fields. Update `Node.Entity`, `EcsQuery`, all comparison sites.
7. Update `Node` static registry key from `ulong` to `ke_entity` (or `(ulong)` packed form).

**Validation**: create entity, destroy it, attempt to use old handle — must return NULL / throw
in debug. No silent access to reallocated slot.

---

### Phase J — Deferred Structural Changes

**Goal**: `AddComponent`, `RemoveComponent`, and `DestroyNode` called during wave execution
are safe and do not corrupt the registry.

**Design:**

Each enkiTS worker thread holds a thread-local `ke_mutation_buffer` (a simple append-only array).
During wave execution, structural changes enqueue entries instead of applying them immediately:

```c
typedef enum {
    KE_MUTATION_ADD_COMPONENT,
    KE_MUTATION_REMOVE_COMPONENT,
    KE_MUTATION_DESTROY_ENTITY,
} ke_mutation_type;

typedef struct {
    ke_mutation_type type;
    ke_entity        entity;
    ke_component_id  cid;
    uint8_t          data[KE_MAX_COMPONENT_SIZE]; // copy of initial value
} ke_mutation_entry;
```

After `enkiTS::WaitForAll()` returns (all waves complete), `world_update` drains all worker
mutation buffers and applies them in order before `end_write`.

**Steps:**
1. Add `ke_mutation_buffer` per-worker in the enkiTS task context.
2. Replace `ke_ecs_component_add` / `remove` / `destroy` with deferred variants when called
   from within a wave (detectable via a `bool wave_active` flag on the world).
3. Drain buffers in `world_update` after wave completion.
4. Update C# `Node.AddComponent`, `RemoveComponent`, `Scene.DestroyNode` to use the deferred
   path transparently — game dev sees no API change.
5. In debug: assert that the immediate (non-deferred) paths are never called during a wave.

**Validation**: a script that destroys another entity during `OnUpdate` must not corrupt
any other system iterating that frame. Entity is visibly absent only on the next frame.

---

### Phase K — Node Static Registry Thread Safety

**Goal**: `Node.s_registry` is safe for concurrent reads from enkiTS workers.

1. Replace `Dictionary<ulong, Node>` with `ConcurrentDictionary<ulong, Node>`.
2. Enforce that writes to the registry (Add/Remove) only happen outside wave execution
   (during setup, teardown, or the deferred mutation drain from Phase J).
3. Add a debug assertion: writes to `s_registry` while `wave_active == true` throw immediately.

**Validation**: two scripts running in parallel can both call `Scene.FindNode` without crash
or torn read.

---

### Phase L — Read/Write Set Enforcement in Debug

**Goal**: a system that lies about its access sets is caught immediately, not silently.

**C kernel changes:**

```c
#ifdef KE_DEBUG
typedef struct {
    ke_component_id cid;
    ke_entity       entity;
    bool            is_write;
    const char*     system_name;
} ke_access_record;
```

The ECS registry maintains a per-frame access log (cleared at `begin_write`). Every call to
`ke_ecs_component_get` or `ke_ecs_component_add` during wave execution appends an entry.
After each wave, the scheduler compares the log against the wave's declared read/write sets.
Any undeclared write triggers an assertion with the system name and component ID.

**Steps:**
1. Add access log to `ke_ecs_registry` (debug-only, zero cost in release via `#ifdef`).
2. Instrument `ke_ecs_component_get` and `ke_ecs_component_add` to record access.
3. Post-wave validation in the scheduler.
4. Log format: `"[ECS VIOLATION] System 'ScriptSystem' wrote ke_transform_component but
   declared only reads"`.

**Validation**: a test system that declares `reads = {}` but calls `AddComponent` triggers
the assertion within one frame.

---

### Phase M — Allocator Semantic Correctness + Draw Capacity Guard

**Goal**: each subsystem uses the allocator type that matches its memory lifetime.
Zero heap allocation on the hot path. Buffer overflows become immediate errors.

**Context**: `allocator.c` already implements `ke_allocator_malloc_create()` and
`ke_allocator_arena_create(capacity)` with a `reset` vtable slot. No new allocator
implementation is needed — only the call sites need to be corrected.

**Allocator assignment by subsystem:**

| Subsystem | Correct allocator | Reason |
|-----------|------------------|--------|
| `ke_ecs_registry` | `arena_allocator` | Grows during setup, never shrinks mid-frame |
| `ke_frame_packet` arrays | `frame_allocator` (arena + auto-reset) | Lifetime = one frame slot |
| `ke_world`, `ke_threading` | `malloc_allocator` | Long-lived, infrequent alloc |
| `ke_logger`, `ke_window` | `malloc_allocator` | IO path, not performance-critical |
| Resource GPU handles | `malloc_allocator` | Async, ref-counted lifetime |

**Frame allocator** is not a new type — it is an `arena_allocator` whose `reset` is called
automatically by `FrameSync` at `begin_write` for each ring buffer slot. Since the ring has
`bufferCount` slots (default 2), each slot owns its own arena instance.

```c
// FrameSync creates one arena per slot — passed to ke_frame_packet at construction
ke_allocator* slot_arena = ke_allocator_arena_create(frame_arena_capacity);
// ... at begin_write:
slot_arena->reset(slot_arena);  // resets offset to 0, no free/malloc
```

The `ke_frame_packet` arrays (`draw_commands`, `point_lights`, `spot_lights`,
`shadow_draw_commands`) are allocated once from the slot arena at `FrameSync::Create`
and never reallocated — they simply point into the arena's fixed buffer.

**Short-term — bounds guard (implement first):**

Every path that writes into a frame packet array must check capacity:

```c
// mesh_system.cpp
uint32_t index = atomic_fetch_add((_Atomic uint32_t*)&packet->draw_count, 1);
if (index >= packet->draw_capacity) {
    atomic_fetch_sub((_Atomic uint32_t*)&packet->draw_count, 1);
    return;  // log once per frame at warning level
}
```

**Steps:**
1. Add bounds check to all `atomic_fetch_add` recording paths: mesh, shadow, point lights,
   spot lights.
2. Add `ke_allocator_frame_create(capacity)` factory in `allocator.c` — returns an arena
   allocator tagged as a frame allocator (semantically identical, distinct name for clarity).
3. `FrameSync` creates one frame allocator per ring slot; passes it to `ke_frame_packet`.
4. `ke_frame_packet` arrays are allocated from the frame allocator at init, pointer stored
   in the packet struct — no change to how systems write draw commands.
5. At `begin_write`, call `slot_arena->reset(slot_arena)` then re-point the packet arrays
   (they point into the same base buffer, reset just moves offset back to 0).
6. Update `ke_ecs_registry_create` to accept a `ke_allocator*` instead of using `malloc`
   internally — caller (World) passes an `arena_allocator`.
7. Update C# `FrameSync.Create` and `World` constructors to pass the correct allocator types.
8. Expose `frameArenaCapacity` and `drawCapacity` as parameters in `FrameSync.Create` with
   defaults (4 MB arena, 2048 draw commands) and a runtime warning at 80% capacity.

**Validation**: submitting 3000 draw commands with capacity 2048 logs a warning and renders
2048 with no memory corruption. Frame time standard deviation decreases under arena allocation.
Valgrind/ASAN reports zero heap allocations during steady-state frame loop.

---

### Phase N — Profiling and Thread Observability

**Goal**: frame spikes and wave imbalances are diagnosable without guesswork.

**Minimal scope profiler:**

```c
// ke_profile.h — zero cost when KE_PROFILE not defined
#ifdef KE_PROFILE
  #define KE_SCOPE(name)  ke_profile_scope_t _scope = ke_profile_begin(name)
  #define KE_FRAME_END()  ke_profile_frame_end()
#else
  #define KE_SCOPE(name)  ((void)0)
  #define KE_FRAME_END()  ((void)0)
#endif
```

Each named thread writes begin/end timestamps into a per-thread ring buffer (no locks, no
cross-thread writes). At frame end, buffers are flushed to a Chrome Trace JSON file or forwarded
to Tracy if available.

**Instrumentation points (first pass):**
- `ke.main`: `PollEvents`, `Input.Update`
- `ke.render`: `SubmitPacket`, `Frame`, `ResourceCommandQueue drain`
- `ke.sim`: `World.Update`, each wave dispatch, each wave wait, `OnUpdate`
- enkiTS workers: each system's `Update` call

**Steps:**
1. Define `ke_profile.h` with `KE_SCOPE` / `KE_FRAME_END` macros, enabled by `KE_PROFILE` flag.
2. Implement per-thread ring buffer writer in C (no allocation, `rdtsc` timestamps).
3. Implement JSON flush at application exit (Chrome Trace format — viewable in any Chromium).
4. Add `KE_SCOPE` to all instrumentation points listed above.
5. Add CMake option `KE_ENABLE_PROFILING` that sets `-DKE_PROFILE`.
6. Optional: Tracy integration behind `KE_PROFILE_TRACY` flag.

**Validation**: running any example with `KE_ENABLE_PROFILING=ON` produces a
`ke_trace_<timestamp>.json` readable in `chrome://tracing` showing all three threads and
enkiTS workers as separate lanes.

---

### Phase O — ABI Stability Strategy

**Goal**: the C kernel API is a stable binary contract. Plugins and the C# P/Invoke layer can
be compiled independently and loaded at runtime without layout mismatches or silent corruption.

**Problem**: today any field addition to `ke_transform_component` or `ke_ecs_registry` shifts
all subsequent fields, breaking every plugin compiled against the old header with no link error.

**Design:**

```c
// Every public kernel struct carries its own size at offset 0
typedef struct {
    uint32_t struct_size;        // set by creator: sizeof(ke_transform_component)
    ke_vec3  position;
    ke_quat  rotation;
    ke_vec3  scale;
    // future fields appended here — old plugins read struct_size and skip unknown tail
} ke_transform_component;

// Every API entry point that receives an external struct validates size
ke_result ke_ecs_component_add(ke_ecs_registry* reg, ke_entity e, ke_component_id cid,
                                const void* data, uint32_t data_size);
// implementation: if (data_size < expected_minimum) return KE_ERROR_ABI_MISMATCH;
```

**Policy:**
- **Add-only**: existing fields are never removed or reordered.
- **Append-only**: new fields are appended at the end of the struct.
- **Size-guarded reads**: readers skip fields beyond the caller's `struct_size`.
- **Version constant**: `KE_KERNEL_ABI_VERSION` incremented on any breaking change.
  Plugins embed the version they were compiled against; the kernel rejects mismatches at load time.

**Steps:**
1. Add `KE_KERNEL_ABI_VERSION` constant to a new `kernel_engine/kernel/version.h`.
2. Prepend `uint32_t struct_size` to every public kernel struct that can be extended.
3. Add `ke_abi_check(struct_size, expected)` inline helper — returns `KE_ERROR_ABI_MISMATCH`
   when `struct_size` is smaller than the minimum known layout.
4. Add `ke_abi_check` to all API entry points that receive externally constructed structs.
5. Document the no-removal/append-only policy in `CLAUDE.md` and `AGENTS.md`.
6. Add a compile-time static assert in each struct's header:
   `static_assert(offsetof(ke_transform_component, rotation) == 4 + sizeof(ke_vec3), "ABI broken");`

**Validation**: compile a plugin against header version N. Apply an additive change (new field).
The plugin still loads and operates correctly against the updated kernel without recompilation.
Removing a field (for testing) causes `ke_abi_check` to return `KE_ERROR_ABI_MISMATCH` at load.

---

### Phase P — Multi-Component ECS Queries

**Goal**: a system that needs two or more components can iterate them with cache-friendly access
and no per-entity pointer lookup overhead.

**Problem**: the current query API returns one component array per call. Any system needing
`Transform + Mesh` must call `ke_ecs_component_get(entity, mesh_cid)` inside the transform
loop — one hash/lookup per entity, per extra component. This defeats the SoA cache benefit.

**Design:**

```c
// Two-component query — returns parallel arrays for entities that have BOTH cids
ke_result ke_ecs_query2(
    ke_ecs_registry* reg,
    ke_component_id  cid_a,
    ke_component_id  cid_b,
    ke_entity**      out_entities,
    void**           out_data_a,
    void**           out_data_b,
    uint32_t*        out_count
);

// Three-component variant
ke_result ke_ecs_query3(
    ke_ecs_registry* reg,
    ke_component_id  cid_a, ke_component_id cid_b, ke_component_id cid_c,
    ke_entity**      out_entities,
    void**           out_data_a, void**  out_data_b, void** out_data_c,
    uint32_t*        out_count
);
```

**Intersection algorithm**: iterate the smallest component set (fewest entities), check presence
in the other sets via sparse-set `has(entity)` — O(min_count × num_extra_sets), no allocation.
Result is written into a scratch buffer pre-allocated from the frame arena (Phase M), reused
each frame without malloc.

**Steps:**
1. Implement `ke_ecs_query2` and `ke_ecs_query3` in the ECS registry.
2. Add scratch buffer (`ke_entity[]` + pointer arrays) to `ke_ecs_registry`, sized at
   `max_entities`, allocated from the registry's arena allocator at creation.
3. Update `MeshRenderSystem`, `ShadowRenderSystem`, `CameraRenderSystem` to use `ke_ecs_query2`
   (all iterate `Transform + their-specific component`).
4. Add C# `EcsQuery2<TA, TB>` and `EcsQuery3<TA, TB, TC>` ref structs mirroring the C API.
5. Update `EcsRegistry` C# wrapper with `Query<TA, TB>` and `Query<TA, TB, TC>` helpers.

**Validation**: `MeshRenderSystem` iterating 10 000 entities with `ke_ecs_query2` shows
measurably lower cache miss count (via `perf stat` or Tracy) than the same count using
`ke_ecs_component_get` per entity in a loop.

---

### Phase Q — Asset System

**Goal**: GPU resources have a formal lifecycle — reference-counted, uniquely identified,
optionally hot-reloadable. No resource leaks at shutdown; no duplicate uploads of the same asset.

**Problem**: resources created in `OnReady` are never formally tracked. A `MeshHandle` is just
an integer. If the caller loses it, the GPU allocation leaks. If two nodes want the same mesh,
each creates its own copy. There is no path for background loading during gameplay.

**Design:**

```csharp
// AssetHandle<T> — ref-counted, strongly typed
public readonly struct AssetHandle<T> : IDisposable
{
    private readonly AssetRegistry _registry;
    private readonly uint          _id;

    public bool  IsValid => _id != uint.MaxValue;
    public void  AddRef()  => _registry.AddRef(_id);
    public void  Dispose() => _registry.Release(_id);  // decrements; destroys at 0
}

// AssetRegistry — singleton per Application, lives on ke.sim
public sealed class AssetRegistry
{
    // Synchronous — blocks ke.sim until ke.render confirms
    public AssetHandle<MeshHandle>    LoadMesh(ke_vertex[] verts, ushort[] indices);
    public AssetHandle<TextureHandle> LoadTexture(string path);      // decodes + uploads
    public AssetHandle<TextureHandle> LoadTexture(int w, int h, byte[] rgba);

    // Async — returns a future, does not block ke.sim
    public ResourceFuture<AssetHandle<TextureHandle>> LoadTextureAsync(string path);

    internal void AddRef(uint id);
    internal void Release(uint id);  // calls IResourceFactory.Destroy when refcount hits 0
}
```

**Steps:**
1. Implement `AssetRegistry` backed by a `Dictionary<uint, (int refcount, object handle)>`.
2. Implement `AssetHandle<T>` as a ref-counted wrapper over `IResourceFactory`-created handles.
3. Integrate `TextureLoader` into `AssetRegistry.LoadTexture` — no longer a free function.
4. Implement `ResourceFuture<T>` — a lightweight awaitable that resolves when ke.render returns
   the handle (backed by `TaskCompletionSource<T>`).
5. `AssetRegistry.Dispose()` (called at engine shutdown) releases all live handles in
   deterministic order (materials before textures, textures before meshes).
6. Update all examples to use `AssetRegistry` instead of direct `IResourceFactory` calls.
7. Add `app.Assets` property to `Application` — resolves from DI.

**Validation**: create 100 mesh assets. Verify GPU resource count via bgfx stats. Drop all
`AssetHandle<T>` references (go out of scope / call Dispose). Verify GPU resource count returns
to baseline. No heap allocations remain in the asset registry after full release.

---

### Phase R — Error Context

**Goal**: when `ke_result` propagates an error through multiple layers, the original cause
(which argument, which invariant, what value) is available in development builds without
forcing the engine into exception-based control flow.

**Problem**: `ke_result` is a bare enum. Three call layers of `if (res != KE_OK) return res`
erase all context. Diagnosing failures in plugins or game code requires printf-debugging every
error site.

**Design:**

```c
// Thread-local error context — zero cost when KE_DEBUG not defined
#ifdef KE_DEBUG

typedef struct {
    ke_result    code;
    const char*  file;
    int          line;
    const char*  function;
    char         message[256];   // human-readable, set via ke_set_error
} ke_error_context;

// Set context at the failure site — one call, no allocation
#define KE_RETURN_ERROR(code, fmt, ...)                              \
    do {                                                             \
        ke_set_error_context((code), __FILE__, __LINE__,            \
                             __func__, (fmt), ##__VA_ARGS__);       \
        return (code);                                              \
    } while (0)

// Read context at the top level (Application, C# exception boundary)
ke_error_context* ke_get_error_context(void);

#else
  #define KE_RETURN_ERROR(code, fmt, ...)  return (code)
#endif
```

Usage:

```c
if (entity.id >= MAX_ENTITIES)
    KE_RETURN_ERROR(KE_ERROR_INVALID_ARG,
                    "entity id %u >= MAX_ENTITIES %u", entity.id, MAX_ENTITIES);
```

On the C# side, `KernelException.ThrowIfFailed` reads `ke_get_error_context()` via P/Invoke
and includes the file/line/message in the exception's `Message` string.

**Steps:**
1. Add `ke_error_context` struct and thread-local storage in a new `error_context.c`.
2. Implement `ke_set_error_context` / `ke_get_error_context` — thin wrappers over
   `__thread ke_error_context` (Linux) / `_declspec(thread)` (Windows).
3. Replace `return KE_ERROR_*` at all ECS and world API entry points with `KE_RETURN_ERROR`.
4. Add P/Invoke binding for `ke_get_error_context` in C# native bindings.
5. Update `KernelException.ThrowIfFailed` to include error context in the exception message.
6. Add `KE_DEBUG` CMake option (enabled by default in Debug builds) that gates the thread-local.

**Validation**: call `ke_ecs_component_add` with an out-of-range entity ID. The C# catch block
receives an exception whose message includes the file name, line, and the specific bad value.
In Release build: no overhead — `KE_RETURN_ERROR` compiles to a bare `return`.

---

### Phase S — Real Plugin Contract

**Goal**: renderer and window backends are true plugins discovered and loaded at runtime, with
version negotiation and no compile-time dependency on their implementation types.

**Problem**: bgfx and GLFW are loaded via direct DLL imports resolved at process startup — not
a plugin model. A third party cannot write an alternative renderer without forking the C# framework.
Swapping backends requires modifying the framework layer and recompiling.

**Design:**

Each plugin DLL exports exactly one symbol:

```c
// Every plugin exports this symbol — the kernel's single load-time entry point
ke_result ke_plugin_register(ke_plugin_context* ctx);
```

`ke_plugin_context` provides:

```c
typedef struct {
    uint32_t         kernel_abi_version;   // from Phase O — kernel declares what it speaks
    ke_allocator*    allocator;
    ke_logger*       logger;

    // The plugin fills in what it provides:
    ke_render_api*   render;               // NULL if this plugin is not a renderer
    ke_window_api*   window;               // NULL if this plugin is not a window provider

    // Version the plugin was built against — kernel rejects mismatch
    uint32_t         plugin_abi_version;
    const char*      plugin_name;
    const char*      plugin_version_str;
} ke_plugin_context;
```

The kernel (`ke_plugin_loader`) discovers plugins by scanning a configured directory for DLLs,
calls `ke_plugin_register` on each, validates `plugin_abi_version` against `KE_KERNEL_ABI_VERSION`,
and wires the provided vtable pointers into the active render/window slots.

**C# side**: `AddBgfxRenderer()` and `AddGlfwWindow()` become `AddPlugin("ke_render_bgfx.dll")`
and `AddPlugin("ke_window_glfw.dll")` — the framework loads, negotiates, and registers without
needing to know the backend type.

**Steps:**
1. Define `ke_plugin_context` and `ke_plugin_register` signature in a new
   `kernel_engine/kernel/plugin/plugin.h`.
2. Implement `ke_plugin_loader` in `plugin_loader.c` — `dlopen`/`LoadLibrary`, symbol lookup,
   ABI version check, vtable wire-up.
3. Rename `ke_render_bgfx_create` → export `ke_plugin_register` in `bgfx` plugin CMake target;
   fill `ctx->render` with the bgfx vtable.
4. Same for GLFW: export `ke_plugin_register`, fill `ctx->window`.
5. Update C# `Application.ConfigureServices`: replace `AddBgfxRenderer` / `AddGlfwWindow` with
   `AddPlugin(string dllPath)` resolved at runtime.
6. Add `PluginLoadException` thrown when ABI version mismatch or symbol not found.
7. Preserve the existing `AddBgfxRenderer` / `AddGlfwWindow` extension methods as thin wrappers
   that call `AddPlugin` with the known DLL name — no breaking change for existing examples.

**Validation**: build a minimal test renderer plugin (stub `ke_render_api` that does nothing)
as a separate DLL. Load it with `AddPlugin`. The engine starts without referencing bgfx at all.
Load the bgfx plugin from a different path — hot-swap test. ABI mismatch (increment
`plugin_abi_version` in the stub) causes a clear `PluginLoadException`.

---

## 4. API Migration Summary

| Before | After |
|--------|-------|
| `app.Renderer.CreateMesh(...)` | `resources.CreateMesh(...)` (from `IResourceFactory`) |
| `app.Renderer.ClearColor(...)` | `scene.ClearColor(...)` (from `ISceneWriter`) |
| `app.Input.IsKeyDown(k)` | `input.IsKeyDown(k)` (from `IInputReader`) |
| `uint meshHandle` | `MeshHandle` (typed, `.None = uint.MaxValue`) |
| `uint textureHandle` | `TextureHandle` (typed, `.None = uint.MaxValue`) |
| `app.OnReady = () => { ... }` | `app.OnReady = (IResourceFactory res) => { ... }` |
| `app.OnUpdate = () => { ... }` | `app.OnUpdate = (ISceneWriter scene, IInputReader input) => { ... }` |

---

## 5. Invariants This Architecture Enforces

After all phases are complete, the following properties hold by construction, not by convention:

1. **No game code reaches bgfx.** `ISceneWriter` and `IResourceFactory` are the only renderer-facing
   interfaces available to game code. Neither calls bgfx. Period.

2. **No shared mutable state between ke.main and ke.sim.** Input travels through `InputBuffer`
   (one-way, lock-free). `ke_message_pipe` is gone.

3. **Resource handles are always valid or explicitly None.** `TextureHandle.None` is
   `uint.MaxValue`, never `0`. Callers must check `.IsValid` — the compiler enforces it for C
   structs, and the C# record types are immutable.

4. **Thread violations are immediate crashes in debug builds, zero overhead in release.**
   No silent misbehavior.

5. **Shutdown always terminates.** Join timeouts guarantee the process exits even under crash
   conditions on ke.render or ke.sim.

6. **enkiTS workers are transparent to game code.** `ISystem.Update` may be called from any
   worker; the contract is documented and enforced through CLR thread attachment.

7. **Stale entity references are detectable.** Entity generation mismatch returns NULL in debug
   and is an asserting error. No silent access to reallocated entity slots.

8. **Structural ECS changes during wave execution cannot corrupt the registry.** Mutations are
   deferred to the post-wave drain. Systems always iterate stable, non-reallocating arrays.

9. **A system cannot silently violate its declared read/write sets.** Debug builds verify every
   component access against the declared set and fail loudly on any undeclared write.

10. **No heap allocation on the frame hot path.** The frame arena resets at `begin_write`. All
    per-frame data is bump-allocated. Frame time is deterministic.

---

## 6. Phase Progress Summary

| Phase | Goal | Status |
|-------|------|--------|
| A — Handle Safety | `UINT32_MAX` sentinel, typed handles | ✅ Done |
| B — Dead Code Removal | Delete `GlfwWindow.cpp` and siblings | ✅ Done |
| C — Thread Affinity | `ke_thread_assert_current`, debug assertions | ✅ Done |
| D — Input Snapshot | `IInputReader`, `InputBuffer`, ke.main → ke.sim | ✅ Done |
| E — ISceneWriter / IResourceFactory | Game dev never touches Renderer | ✅ Done (examples migrated) |
| F — Structured Shutdown | `CancellationTokenSource`, join timeouts | ✅ Done — cv-based `JoinTimeout` is cross-platform; no `#ifdef` |
| G — enkiTS CLR Safety | CLR thread attachment for workers | 🔲 Planned |
| H — Remove MessagePipe | Delete `ke_message_pipe` entirely | ✅ Done |
| I — Entity Generations | `{ id, generation }`, stale ref detection | 🔲 Planned |
| J — Deferred Structural Changes | Mutation buffers, post-wave drain | 🔲 Planned |
| K — Node Registry Thread Safety | `ConcurrentDictionary`, wave-time write guard | 🔲 Planned |
| L — Read/Write Set Enforcement | Debug access log, post-wave validation | 🔲 Planned |
| M — Frame Arena + Capacity Guard | Zero malloc on hot path, overflow protection | 🔲 Planned |
| N — Profiling & Observability | Per-thread ring buffer, Chrome Trace output | 🔲 Planned |
| O — ABI Stability | `struct_size` guards, version constant, append-only policy | 🔲 Planned |
| P — Multi-Component Queries | `ke_ecs_query2/3`, intersection, scratch buffer | 🔲 Planned |
| Q — Asset System | `AssetHandle<T>`, ref counting, async loading, `AssetRegistry` | 🔲 Planned |
| R — Error Context | Thread-local `ke_error_context`, `KE_RETURN_ERROR` macro | 🔲 Planned |
| S — Real Plugin Contract | `ke_plugin_register`, runtime discovery, ABI negotiation | 🔲 Planned |

### Track Y — Observability Status

| Item | Goal | Status | Commit |
|------|------|--------|--------|
| Y.1 (DB-01) | bgfx fatal callback — capture file/line/code | ✅ Done | a409f95 |
| Y.2 (DB-02) | `LogErr` C++ helper — log every silent error path | 🔲 Planned | — |
| Y.3 (DB-03) | Debug logging in bgfx init | 🔲 Planned | — |
| Y.4 (DB-04) | Symbolic `ke_result` names in `KernelException` | ⚠️ Partial | e519eda |
| Y.5 (DB-05) | Audit `_ =` Result discards | 🔲 Planned | — |
| Y.6 (DB-06) | Top-level exception handler in `Application.Run` | ✅ Done | 499c177 |
| Y.7 (DB-07) | Synchronous flush in log sinks | ✅ Done | 8197ec1 |
| Y.8 (DB-08) | Native SEH crash handler | ✅ Done | 499c177 |
| Y.9 (DB-09) | Startup lifecycle logging | ✅ Done | 499c177 |
| **Y.10 (NEW)** | **Bindings-drift detection in CI** — fail build if `ke_*.h` mtime > `Generated/*.cs` mtime, motivated by bug 1.25 (30-min lost) | 🔲 Planned | — |

### Bug Catalog Status (post-Phase-E session)

| # | Title | Status | Fixed in |
|---|-------|--------|----------|
| 1.22 | `ke_system_desc` carries `ke_render*` | 🔄 ShadowSystem fixed; ABI cleanup pending | 0e84485 |
| 1.23 | OnReady ResourceCommandQueue deadlock | ✅ Workaround (`simReady` event) | fde78a9 |
| 1.24 | `KeThread` thread-name use-after-free | ✅ Fixed | 1481ef4 |
| 1.25 | `ke_input` C# binding out-of-sync with C struct | ✅ Fixed + audit needed for other structs | 3583586 |
| 1.26 | `ke_thread_set/get/assert_current` declared in kernel header but implemented in `ke_threading.dll` → ClangSharp generated `DllImport("ke_kernel")` for symbols not in `ke_kernel.dll`, causing `EntryPointNotFoundException` at runtime | 🔄 Symptom patched (route through Threading.Native); proper fix is Track W.4 (move impl to ke_kernel C, restore declarations in kernel header) | (pending) |

### Tech Debt Carry-Over

| Item | Why deferred | When to address |
|------|--------------|-----------------|
| `ke_thread_desc` → `ke_thread_params` rename | All other `_desc` were standardized to `_params`; threading was missed. Cosmetic, no functional impact. | Bundle with next bindings regen pass |
| ~~`KeThread::JoinTimeout` Linux busy-wait~~ | ✅ **Resolved** — replaced by `condition_variable::wait_for` (cross-platform). | Done in 3fb4835 |
| `CameraNode.OnStart` runs every frame | `s->started=true` IS set in C; verified working. False alarm. | N/A |
| SEH crash handler + minidump still in `Application.cs` | Win32-only code lives inside generic framework. Should move into `IDevPlatform` (Track P, Wave 2). | Track P, Wave 2 |
| `Allocator.aligned_alloc` if added | Use `std::aligned_alloc` (C++17) directly, NOT `IDevPlatform`. Listed here as reminder of the admission rule. | When the need arises |

---

## Track P — Platform Abstraction Layer

### Admission rule (mandatory before adding anything to `IDevPlatform`)

```
1. Is the operation actually needed? → if no, drop it.
2. Does std/C++ already provide it cross-platform? → if yes, use std directly. NEVER add to IDevPlatform.
3. Can it be implemented on every platform we care about (Windows, iOS, Android, WebGL, consoles)?
   → if yes: add to IDevPlatform with a no-op fallback for platforms without the capability.
   → if no: it's dev-only. Implement only for Win/Linux/macOS. Game code MUST tolerate its absence.
4. If it's impossible on a major shipping target → reconsider whether we want it at all.
```

This rule was applied retroactively and **dropped several initially-considered items**:
`set_thread_affinity` (proibido em iOS, restrito em Android), `JoinTimeout` (std::condition_variable
resolves it), `aligned_alloc` (C++17 std), `query_perf_counter` (std::chrono).

### Wave 1 — Foundation ✅ Done

| Item | Where | Status |
|------|-------|--------|
| `IDevPlatform` C ABI | `src/c/kernel/include/.../dev_platform/dev_platform.h` | ✅ |
| `Win32DevPlatform` (`SetThreadDescription`) | `src/cpp/dev_platform/win32/` | ✅ |
| `PosixDevPlatform` (`pthread_setname_np`) | `src/cpp/dev_platform/posix/` (Linux + macOS) | ✅ |
| Eliminate all `#ifdef` from `KeThread.cpp` | std::thread + cv only | ✅ (3fb4835) |
| Cross-platform `JoinTimeout` | `condition_variable::wait_for` + `atomic<bool>` shared state | ✅ |
| `DevPlatform` C# wrapper | `src/csharp/KernelEngine.Kernel/DevPlatform.cs` | ✅ |
| `KernelEngine.DevPlatform.Win32` DI extension | `AddWin32DevPlatform()` | ✅ |
| `Application` consumes optional `DevPlatform` from DI | `ke.main`, `ke.render`, `ke.sim` get OS-visible names when registered | ✅ |

### Wave 2 — Move Win32-only diagnostics out of generic framework

| Item | Why | Status |
|------|-----|--------|
| `IDevPlatform.InstallCrashHandler(callback)` | Today `Application.cs` calls `SetUnhandledExceptionFilter` directly — leaks Win32 into the generic framework | 🔲 Planned |
| `IDevPlatform.WriteMinidump(path, ctx)` | Today minidump generation is in `Application.cs` — same Win32 leak | 🔲 Planned |
| Move SEH + minidump code from `Application.cs` to `Win32DevPlatform` | Framework becomes Win32-free | 🔲 Planned |
| Add `KernelEngine.DevPlatform.Posix` DI extension | Symmetric to Win32, signal-based crash handler | 🔲 Planned |

### Wave 3+ — On demand only (must pass admission rule)

| Candidate | Verdict |
|-----------|---------|
| `LoadLibrary` / `dlopen` (hot-reload of plugins) | Dev-only — proibido em iOS/consoles. Add only if hot-reload becomes a real need. |
| `WatchFile` (asset hot-reload) | Dev-only — sandbox em mobile, n/a em WebGL. Add when asset pipeline justifies. |
| `set_thread_affinity` | **Rejected by admission rule** — proibido em iOS, restrito em Android. If ever needed, becomes a no-op on those platforms. |

---

## 7. Risks and Open Questions

- **ResourceCommandQueue backpressure**: if ke.sim produces resource creation commands faster
  than ke.render consumes them, what is the behavior? Options: block ke.sim (simplest, deadlock-safe),
  drop with error (unsafe), grow unbounded (memory risk). Decision deferred to Phase E.

- **Async resource loading**: `CreateMeshAsync()` returning a `ResourceFuture<MeshHandle>` that
  resolves next frame requires the game developer to handle the pending state. The ergonomics of
  this pattern (checking `.IsReady`, registering callbacks) need to be designed carefully.

- **`ISceneWriter` lifetime enforcement**: the writer wraps a raw `ke_frame_packet*`. If game
  code stores it past `EndWrite`, it becomes a dangling pointer. In C# this requires careful
  design — possibly making `ISceneWriter` a `ref struct` to prevent capture.

- **World.Update signature change**: if `IInputReader` is passed into `World.Update`, the C kernel
  needs to propagate it through the system graph. The cleanest path may be to add
  `ke_input_snapshot*` to `ke_frame_packet` directly, making it part of the frame boundary.

- **`simReady` spin-drain is a temporary workaround**: the `ManualResetEventSlim` + `SpinWait(100)`
  pattern in `Application.Run()` eliminates the deadlock but burns CPU during startup and is
  fragile in the face of future threading changes. The proper fix (section 2.10) requires
  `ResourceCommandQueue` and `FrameSync` to expose semaphore handles for `WaitHandle.WaitAny`.
  Until that is implemented, keep the spin-drain but do not extend it to cover new use cases.

- **`ke_system_desc` carries `ke_render*` — enforcement gap**: removing the pointer from
  `GetDescription` signatures will break all callers. The migration must be done in one commit per
  system (ShadowSystem first, since it is the worst offender) with a compile-error check: if
  `ke_render*` appears in any `ke_system_desc` field after the migration, the build fails.

---

## 8. Additional Tracks

Concerns orthogonal to the threading/ECS/infrastructure phases. Each track is independent and
can be assigned and executed in parallel with the numbered phases.

---

### Track T — Testing

#### T.1 Unit Tests
Already established. Continue expanding coverage per subsystem.

#### T.2 E2E Testing — Two-Layer Strategy

**Layer 1: Automated screenshot regression (CI)**

Each example is run headlessly (or with a deterministic seed) and captures a frame as PNG.
The PNG is compared against a stored *golden image* with a pixel tolerance threshold.
CI fails if the diff exceeds the threshold. Humans act only when a visual change is intentional:
approve the new golden image and commit it.

```
examples/
  golden/
    01_window_scene.png
    02_textured_quad.png
    ...
test_runner/
  screenshot_diff.py   # renders each example → captures PNG → diffs against golden
```

Implementation uses bgfx's `BGFX_RESET_CAPTURE` flag + `bgfx::requestScreenShot()` to dump
a frame to disk without a visible window. A Python or C# CLI script drives each example
binary, waits for one rendered frame, saves the PNG, and diffs.

**Layer 2: Human sign-off runner (exploratory)**

A separate binary or CLI mode runs all examples sequentially in a window, displaying a HUD:
- Example name and description ("Expected: a PBR sphere with directional shadow")
- Two buttons: `[Pass]` / `[Fail]`

At the end, prints a report to stdout mirroring unit test output:

```
[PASS] 01_window_scene
[PASS] 02_textured_quad
[FAIL] 03_pbr_directional — marked by tester
[PASS] 04_normal_map
...
5/6 passed, 1 failed
```

This layer runs manually before releases. It does not block CI.

**Steps:**
1. Add `BGFX_RESET_CAPTURE` path to the renderer for headless mode.
2. Implement `ke_screenshot_runner` CLI: runs example → captures frame → exits.
3. Write `scripts/screenshot_diff.py` using Pillow: loads golden + captured, computes per-pixel
   RMSE, fails if above threshold (default 2.0/255).
4. Add golden images for examples 01–N at baseline.
5. Add CI step: `python scripts/screenshot_diff.py --all`.
6. Implement the human runner binary (Layer 2) with pass/fail HUD using bgfx UI overlay or
   a simple terminal prompt.

---

### Track U — Tooling

#### U.1 VSync Exposed as Configuration

**Problem**: `BGFX_RESET_VSYNC` is hardcoded in `bgfx_gpu_device.cpp:95`.
`WindowConfig.vsync` exists in `window_types.hpp` but is never read or wired up.

**Fix**:
1. Read `WindowConfig.vsync` in `BgfxGpuDevice::Init`.
2. Map to `BGFX_RESET_VSYNC` or `BGFX_RESET_NONE` accordingly.
3. Expose in C# as `AddBgfxRenderer(..., vsync: false)` parameter.
4. Default: vsync enabled (current behavior preserved). Without vsync the engine runs
   uncapped — for a simple quad + skybox, thousands of FPS on any modern GPU.

**Validation**: `AddBgfxRenderer(shaderPath, vsync: false)` → FPS counter shows uncapped
framerate well above monitor refresh rate.

#### U.2 bgfx `abort()` → Structured Error Reporting

**Problem**: bgfx calls `abort()` on fatal errors (wrong-thread API calls, invalid state).
This produces a process crash with no stack trace, no log entry, and no context. Diagnosing
what went wrong requires guesswork.

**Fix**: bgfx exposes `bgfx::CallbackI` — a virtual interface with a `fatal()` method that
bgfx calls instead of `abort()` when a custom callback is registered.

```cpp
class KernelBgfxCallbacks : public bgfx::CallbackI
{
    void fatal(const char* filePath, uint16_t line,
               bgfx::Fatal::Enum code, const char* str) override
    {
        ke_log_error("bgfx", "[%s:%d] fatal(%d): %s", filePath, line, (int)code, str);
        // flush log, then throw or set a flag for the render thread to handle
        throw std::runtime_error(str);  // caught at render thread boundary
    }
    // ... traceVargs, profileBegin/End, etc.
};
```

The `KernelBgfxCallbacks` instance is passed to `bgfx::init`. The render thread's top-level
try/catch converts the C++ exception into a `KernelException` on the C# side with the full
bgfx message, file, and line number.

**Steps:**
1. Implement `KernelBgfxCallbacks : public bgfx::CallbackI` in `bgfx_gpu_device.cpp`.
2. Pass instance to `bgfx::init` via `init.callback`.
3. Implement `fatal()` to log + throw `BgfxFatalException`.
4. Wrap render thread top-level loop in try/catch to propagate to C# as `KernelException`.
5. Implement `traceVargs()` to route bgfx debug traces through `ke_logger`.

**Validation**: call a bgfx API from the wrong thread in a test — instead of a silent `abort()`,
the render thread unwinds with a structured exception containing the bgfx file/line/message.

#### U.3 ClangSharp `.rsp` Cleanup — Remove `--exclude` Hacks

**Problem**: `.rsp` files use `--exclude` lists that grow as new forward declarations appear
in generated bindings. This is a maintenance burden and the wrong tool for the job.

**Fix**: use ClangSharp's `--include-directory` and explicit traversal configuration to control
what is generated, rather than blacklisting post-generation. Alternatively, use a
`[NativeTypeName]` attribute strategy to let ClangSharp emit stubs correctly without
requiring nested-struct exclusions.

**Steps:**
1. Audit each `.rsp` file — identify every `--exclude` and why it exists.
2. For nested-stub cases: add `--remap` or explicit type aliases to eliminate the nested forward decl.
3. For unrelated-type cases: use `--include-directory` to limit traversal scope.
4. Remove all `--exclude` entries. Confirm generated output is identical.
5. Document the correct `.rsp` pattern in `CLAUDE.md`.

#### U.4 Asset Loading in C++ (not C#)

**Problem**: `TextureLoader.cs` uses `SixLabors.ImageSharp` — a C# library. This violates the
engine's architecture principle: implementations live in C/C++, C# is only the wrapper layer.
A Rust or Python consumer of the engine would have to re-implement texture loading.

**Fix**: implement image decoding in C++ using `stb_image` (already available via vcpkg).

```c
// ke_image_loader.h — C API
typedef struct {
    uint8_t* data;       // RGBA8 pixel data, caller must free via ke_allocator
    uint32_t width;
    uint32_t height;
    uint32_t channels;   // always 4 after load
} ke_image;

ke_result ke_image_load_file(ke_allocator* alloc, const char* path, ke_image* out);
ke_result ke_image_free(ke_allocator* alloc, ke_image* image);
```

The C# `TextureLoader` becomes a thin P/Invoke wrapper over `ke_image_load_file` — no ImageSharp
dependency, no C# memory management for pixel data.

**Steps:**
1. Add `stb_image` to vcpkg manifest if not already present.
2. Implement `ke_image_load_file` / `ke_image_free` in `src/c/kernel/src/assets/image_loader.c`.
3. Expose in `ke_kernel` public headers.
4. Add P/Invoke binding in C# native bindings layer.
5. Rewrite `TextureLoader.cs` to call native `ke_image_load_file` instead of ImageSharp.
6. Remove `SixLabors.ImageSharp` from C# project dependencies.

#### U.5 Shader Compilation for Multiple Backends

**Problem**: the shader compile script targets Vulkan (`-p spirv`) only. If the engine gains
DX12 or Metal support (via Phase S plugin contract), shaders would need recompilation for
each backend.

**Fix**: extend the script to compile for all configured targets and place outputs in
backend-named subdirectories:

```
shaders/
  compiled/
    spirv/   vs_basic.bin, fs_basic.bin
    dx11/    vs_basic.bin, fs_basic.bin
    metal/   vs_basic.bin, fs_basic.bin
```

At init time, `BgfxGpuDevice` detects the active renderer type and loads from the correct
subdirectory. The game developer only specifies the base shader path.

**Steps:**
1. Extend `scripts/compile_shaders.py` (or `.ps1`) to accept `--targets spirv,dx11,metal`.
2. Update `AddBgfxRenderer(shaderPath)` to append backend suffix at runtime.
3. Gate DX11/Metal targets behind `KE_SHADER_TARGETS` CMake option (default: spirv only).

#### U.6 Git Hygiene — Remove Agent Files from History

**Problem**: `AGENTS.md`, `CLAUDE.md`, `.claude/` directory contain AI instruction files that
should not be part of the public repository history.

**Fix:**
1. Add to `.gitignore`: `.claude/`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` (any AI config).
2. Use `git filter-repo` to scrub from history if the repo will be made public.
3. Note: if CLAUDE.md is intentionally checked in as project instructions (per Anthropic docs),
   keep it but add `.claude/` (the local cache dir) to `.gitignore`.

---

### Track V — Rendering

#### V.1 Vulkan Semaphore Warnings

bgfx Vulkan backend emits semaphore-related validation warnings. These are typically caused
by submitting to a queue that has pending semaphore signals, or by not properly synchronizing
present/acquire operations. Investigate with Vulkan validation layers (`VK_LAYER_KHRONOS_validation`)
in verbose mode to identify the exact validation message and the bgfx path that triggers it.

**Steps:**
1. Enable `VK_LAYER_KHRONOS_validation` in the bgfx init (set env `VK_INSTANCE_LAYERS`).
2. Capture full validation output for one frame.
3. Identify whether the warning is in bgfx itself (upstream bug → report/workaround) or in
   our initialization sequence (fixable).
4. If bgfx bug: add to `7. Risks and Open Questions` with a link to the upstream issue.

#### V.2 bgfx Abort Capture
*(Covered in Track U.2)*

---

### Track W — Architecture Cleanup

#### W.1 Codebase Audit — Orphaned Files and Wrong-Domain Code

A full audit to eliminate dead weight that has accumulated over multiple refactoring passes.

**Checklist:**
- [ ] Phantom headers: `.h`/`.hpp` files with no `.cpp`/`.c` implementation and no includers.
- [ ] Orphaned implementations: `.cpp`/`.c` files not referenced in any `CMakeLists.txt`
      `target_sources()` — these compile but do not link, making them invisible dead code.
- [ ] Super-headers: headers that include nearly everything — they force full recompilation on
      any change and hide real dependency structure.
- [ ] Wrong-domain code: C# classes in `KernelEngine.Kernel` that are not direct wrappers
      of native types (they belong in `KernelEngine.Framework`).
- [ ] `CMakeLists.txt` audit: unused variables, stale `target_link_libraries`, duplicated
      `target_include_directories`, wrong install destinations.
- [ ] Unused exported symbols: C API functions declared in public headers with no caller.
- [ ] Redundant projects: evaluate whether `KernelEngine.Kernel.Native` (generated bindings)
      and its plugin equivalents need to be separate projects or can collapse.

**Steps:**
1. Run `grep -r '#include' src/ | sort | uniq -c | sort -rn` — identifies most-included headers.
2. Cross-reference every `.cpp`/`.c` against `CMakeLists.txt` `target_sources` lists.
3. Run `nm --defined-only` on each compiled library, cross-reference against headers.
4. For each finding, classify: delete / move / document-as-intentional.

#### W.2 Godot-Like Composable Scenes

**Goal**: scenes are serializable, composable assets — not just runtime node trees.
A `SceneAsset` (`.kscene` file) defines a node hierarchy. Any node in a hierarchy can
be a reference to another scene asset, creating composable prefabs.

```
player.kscene
  MeshNode (body)
  CameraNode (eye)
  player.kscene#weapon_slot
    weapon.kscene
      MeshNode (blade)
      MeshNode (handle)
```

**Design choices to decide before implementation:**
- File format: JSON (human-readable, easy tooling) vs binary (fast load, smaller).
- Hot reload: should editing a `.kscene` file update running instances?
- Relation to ECS: scene nodes become ECS entities on instantiation; the `.kscene` is just
  a recipe.

This is a Framework-level feature — the kernel ECS and C layer are unaware of it.

**Steps (design phase — not ready to implement):**
1. Define `.kscene` JSON schema.
2. Implement `SceneAsset` C# class: load from file, instantiate into a `World`.
3. Implement `SceneNode` C# node: reference to a `SceneAsset`, instantiated as child hierarchy.
4. Integrate with `AssetRegistry` (Phase Q) for caching and hot reload.

#### W.3 Resource Cache / Deduplication

**Problem**: currently two nodes that want the same mesh each create separate GPU uploads.
No deduplication, no reference counting by path/content.

**Fix**: `AssetRegistry` (Phase Q) is the natural home for this. When loading by path,
check if the asset is already registered — return the existing `AssetHandle<T>` and
increment its refcount instead of re-uploading.

Key: cache key = normalized file path. For programmatic assets (vertex data passed directly),
caching is opt-in via a caller-provided key.

*(Detailed implementation in Phase Q.)*

#### W.4 [HIGH] Layer Boundary Cleanup — Plugins Leaking Beyond `_create()`

**Background:** the engine convention (now formalized in `CLAUDE.md` and the layer-boundary
memory rule) is that **public engine API lives only in `src/c/kernel/include/`**, and each
`src/cpp/<plugin>/` exposes **exactly one** public symbol: its `ke_<plugin>_create()` entry
point. Everything else under `src/cpp/` is implementation detail.

This rule was violated in several places — discovered when an `EntryPointNotFoundException`
crash exposed a binding that pointed to `ke_kernel.dll` for functions actually exported by
`ke_threading.dll`. Root cause: the kernel header declared functions that were implemented
in a plugin, AND the plugin's public header re-declared the same functions plus extras.

**Known violations to fix:**

| Location | Violation | Required fix |
|---|---|---|
| `src/cpp/threading/include/.../thread.h` | Exposes `ke_thread_set_current_name`, `get_current_name`, `assert_current` (TLS thread-name utilities) — these are NOT plugin-specific factories | Move impl to `src/c/kernel/src/threading/thread.c` using C11 `_Thread_local`; declare in `src/c/kernel/include/.../threading/thread.h`; remove from cpp wrapper. The cpp wrapper keeps only `ke_thread_std_create` |
| `src/cpp/threading/include/.../semaphore.h` | Currently OK in isolation (only the factory) but inconsistent with the bgfx single-header convention | Consider consolidating threading into a single `kernel_engine/threading/threading.h` exposing all 3 factories (`thread_std_create`, `semaphore_std_create`, `frame_sync_std_create`) |
| `src/cpp/threading/include/.../frame_sync.h` | Same as above | Consolidate per above |
| `src/cpp/dev_platform/win32/src/win32_dev_platform_public.h` | Public header lives in `src/`, not `include/` | Move to `src/cpp/dev_platform/win32/include/kernel_engine/dev_platform/win32/dev_platform_win32.h` to match bgfx/glfw convention |
| **Audit pass** | Any other `.h` (not `.hpp`) under `src/cpp/<plugin>/include/` containing more than the create function | Inventory all and classify: move to kernel / keep as factory-only / make private `.hpp` |

**Why this is HIGH priority (not LOW housekeeping):**
1. Today's bug — `EntryPointNotFoundException` because the header lied about where the impl
   lives — is a direct consequence of this violation. Same class of bug will reoccur.
2. Mixing plugin-specific and generic declarations in the same header makes ClangSharp generate
   wrong `DllImport` library paths, silently. Hours lost diagnosing.
3. Without strict separation, adding a new backend (DirectX renderer, Wayland window) requires
   reading every plugin's headers to understand what's contract vs implementation — friction
   compounds with each new backend.

**Definition of done:**
- Every `.h` under `src/cpp/<plugin>/include/` contains nothing more than the plugin's create
  function and any tightly-related public types it returns.
- Every TLS/utility/cross-cutting function the engine relies on is implemented in C and lives in
  `ke_kernel`.
- A simple grep can verify: `find src/cpp -path '*/include/*' -name '*.h' | xargs wc -l` —
  each file should be small and obvious.
- CLAUDE.md rule passes the audit checklist documented in section 2.11.

---

### Track X — Rendering Features Backlog

Items pending from the rendering roadmap. All features listed as Done in `ROADMAP.md` are
confirmed complete. The three remaining items:

#### X.1 Depth Prepass (Early-Z)

**Goal**: reduce overdraw by running a geometry-only pass before the main scene pass.
Fragments that would be overdrawn fail the depth test and are discarded before the expensive
PBR fragment shader runs.

**Design**: always-on pass on view 0 (currently shadow). Shadow pass moves to view 1, scene to
view 2. Depth buffer from the prepass is shared with the HDR framebuffer using
`BGFX_TEXTURE_RT_WRITE_ONLY` so the scene pass uses `DEPTH_TEST_EQUAL` instead of
`DEPTH_TEST_LESS`.

**Validation**: enable overdraw visualization in bgfx debug mode (`BGFX_DEBUG_OVERDRAW`).
Overdraw count on geometry should visibly drop when prepass is active.

#### X.2 KTX2 / Compressed Textures

**Goal**: GPU-compressed textures (BC7/ASTC) with embedded mipmaps loaded directly without
CPU decode. Eliminates the current CPU mipmap box-filter path for large textures.

Requires: `ktx` library (via vcpkg), bgfx `createTexture` with `BGFX_TEXTURE_NONE` flags for
pre-compressed data. The `ke_image_load_file` API (Track U.4) would gain a `ke_image_load_ktx`
variant.

#### X.3 Offline Asset Pipeline

**Goal**: bake glTF + PNG → engine binary format at build time. Runtime loading reads only
pre-processed binary — no Assimp, no stb_image at runtime.

This is a prerequisite for shipping a game. Design deferred to Phase Q (Asset System) which
must define the binary format and `AssetHandle<T>` lifecycle first.

---

### Track Y — Observability

Based on the detailed observability plan in the original ROADMAP.md. Track U.2 covers bgfx
abort capture; this track covers the full observability picture.

> DB-01 overlaps with Track U.2 — implement them together.

#### Y.1 (DB-01) bgfx Callback — Fatal and Trace

*(See Track U.2 for full design.)*

Implement `KernelBgfxCallbacks : public bgfx::CallbackI`:
- `fatal()` → log `KE_LOG_LEVEL_ERROR` with bgfx file/line/code, then throw `BgfxFatalException`.
- `traceVargs()` → format with `vsnprintf`, emit `KE_LOG_LEVEL_DEBUG` tagged `"bgfx"`.
- Pass to `bgfx::init`. Enable `init.debug = true` in non-Release builds to activate
  bgfx internal validation and `VK_LAYER_KHRONOS_validation`.

**Acceptance**: the old `setBuffer+submit` crash produces `[ERROR][bgfx] ...` in the log
before termination, instead of a silent `0x80000003`.

#### Y.2 (DB-02) `LogErr` Helper for C++ `ke_result` Paths

Create a local helper in C++ render code:

```cpp
static ke_result LogErr(ke_logger* log, ke_result r,
                         const char* ctx, const char* detail) {
    ke_log_error(log, "render", "[%s] %s", ctx, detail);
    return r;
}
```

Replace every `return KE_ERROR_*` that has a `logger_` in scope with
`return LogErr(logger_, KE_ERROR_*, __func__, "detail")`.

#### Y.3 (DB-03) Debug Logging in Initialization

In `BgfxGpuDevice::Init` (or equivalent), add `KE_LOG_LEVEL_DEBUG` lines for:
- Resolved shader path and whether the file exists on disk.
- Result of each `load_shader()` call: name + valid/invalid.
- Result of each `createUniform()`, `createFrameBuffer()`.
- At the end: GPU vendor name and renderer type from `bgfx::getCaps()`.

**Acceptance**: with `KE_LOG_LEVEL_DEBUG`, a missing shader produces
`[DEBUG][bgfx] load_shader("fs_basic"): NOT FOUND at shaders/fs_basic.bin`.

#### Y.4 (DB-04) Enrich `KernelException` with Symbolic Result Names

```csharp
public static class KernelException
{
    private static readonly Dictionary<int, string> ResultNames = new()
    {
        [(int)ke_result.KE_ERROR_RENDER]            = "KE_ERROR_RENDER",
        [(int)ke_result.KE_ERROR_INVALID_ARGUMENT]  = "KE_ERROR_INVALID_ARGUMENT",
        // ...
    };

    public static void ThrowIfFailed(ke_result r, string context = "")
    {
        if (r == ke_result.KE_OK) return;
        var name = ResultNames.GetValueOrDefault((int)r, $"ke_result({(int)r})");
        throw new KernelException($"{name}{(context.Length > 0 ? $" in {context}" : "")}");
    }
}
```

#### Y.5 (DB-05) Audit `_ =` Result Discards in Framework

Grep for `_ =` in `KernelEngine.Framework`. For each:
- If the call can fail: replace with `KernelException.ThrowIfFailed(result, nameof(method))`.
- If failure is truly expected and harmless: add an explicit comment explaining why.

#### Y.6 (DB-06) Top-Level Exception Handler in `Application.Run()`

Wrap the main loop body in `try/catch(Exception ex)` that logs via logger before rethrowing.
Guarantees exceptions appear in the log even if the sink doesn't auto-flush on unwind.

#### Y.7 (DB-07) Synchronous Flush in Log Sinks

Verify `ConsoleSink` and any future sinks write synchronously — no internal buffer that
survives a crash unwritten. If buffering exists, call `Flush()` at the end of each `Log()`.

#### Y.9 (DB-09) Startup Lifecycle Logging

Log one line per major initialization milestone so that a silent crash during startup can be
pinpointed without a debugger:

```
[INFO][Application] ke.render: initializing renderer
[INFO][Application] ke.render: shadow map created (1024×1024)
[INFO][Application] ke.render: renderer ready — signaling ke.sim
[INFO][Application] ke.sim: OnReady complete — entering frame loop
[INFO][Application] ke.main: first frame rendered
```

Each line must be emitted by the thread that owns that milestone and must appear before the
thread enters its blocking loop. Missing lines identify exactly which phase hung or crashed.

**Acceptance**: killing the process at any point during startup leaves the last printed line
identifying the last successfully completed phase.

#### Y.8 (DB-08) Native SEH Crash Handler

Register `SetUnhandledExceptionFilter` via P/Invoke before starting the loop:

```csharp
[DllImport("kernel32")]
static extern IntPtr SetUnhandledExceptionFilter(IntPtr handler);
```

The handler writes directly to `Console.Error` (logger state may be corrupt):
```
[FATAL] Native crash SEH 0x80000003 (STATUS_BREAKPOINT — bgfx debug assert)
```

Common codes to map:
- `0x80000003` = STATUS_BREAKPOINT (bgfx assert / `debugBreak()`)
- `0xC0000005` = ACCESS_VIOLATION
- `0xC00000FD` = STACK_OVERFLOW

Calls `Environment.Exit(1)` to guarantee a non-zero exit code.

**Acceptance**: the original crash (`setBuffer+submit`) produces
`[FATAL] Native crash SEH 0x80000003 (STATUS_BREAKPOINT — bgfx debug assert)` in stderr
before terminating.

---

### Track Z — Examples Completion

Examples are the E2E integration tests for the engine. Each one validates a feature slice
end-to-end from C# Framework to GPU output.

**Log contract** (all examples must comply):

At startup:
```
[KernelEngine] Example: <name>
[KernelEngine] Renderer: bgfx/Vulkan
[KernelEngine] Features: <comma-separated active features>
```

Every 5 seconds:
```
[KernelEngine] FPS: <value>  Entities: <count>  Lights: <Np Ns Nd>
```

On any `ke_result != KE_OK`:
```
[KernelEngine] ERROR: <function> returned <code>
```

**Complexity ladder:**

| # | Name | What it tests | Expected visual |
|---|------|---------------|-----------------|
| 01 | `01_window_scene` | Window, clear color, main loop, spinning node | Cycling background, rotating orange quad |
| 02 | `02_textured_quad` | Texture loading (PNG), albedo material, UV | Quad with PNG image |
| 03 | `03_pbr_directional` | PBR GGX, directional light, camera orbit | Lit sphere with moving specular highlight |
| 04 | `04_normal_map` | Normal map pipeline, TBN | Flat quad that looks like a brick surface |
| 05 | `05_skybox_ibl` | Cubemap, skybox, IBL reflections | Reflective sphere inside a skybox |
| 06 | `06_shadow_map` | Shadow pass, depth bias, shadow receiving | Hard shadow from box onto ground plane |
| 07 | `07_point_lights` | Clustered Forward — N point lights | Multiple colored lights illuminating scene |
| 08 | `08_spot_lights` | Spot lights, inner/outer cone falloff | Flashlight-style cone illumination |
| 09 | `09_many_lights` | Clustered scaling — 256 point lights | Dense light field, stable FPS, no visible cap |
| 10 | `10_postfx` | HDR tonemapping + bloom | Emissive areas bleeding light |
| 11 | `11_ssao` | SSAO prepass, hemisphere kernel | Crevices and corners darkened by AO |
| 12 | `12_asset_loader` | Assimp glTF load, texture dedup | DamagedHelmet (or similar) with PBR materials |
| 13 | `13_full_scene` | All features combined, FPS ≥ 30 @ 1080p | glTF model, skybox, shadow, 32 lights, SSAO, bloom |

**Current status**: examples 01–05 implemented; 06–13 pending.

**Notes:**
- Example 01–05 compilation errors from Phase E API migration (handle types, `OnReady`/`OnUpdate`
  signatures) need to be fixed before any new example is added.
- Each example should be added to the screenshot regression suite (Track T.2, Layer 1) as its
  golden image is captured.
- Example 13 serves as the synthetic benchmark: if FPS drops below 30 at 1080p on reference
  hardware, it is a regression.

---

## 9. Decisions Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Remove `ke_message_pipe` entirely (Phase H) | No remaining consumers after Phase D; Observer pattern added later when a concrete game-level use case demands it |
| 2 | E2E testing: two-layer (automated screenshot diff + manual runner) | Screenshot diff catches regressions in CI without human intervention; manual runner handles subjective visual review before releases |
| 3 | VSync hardcoded ON → expose as parameter | `WindowConfig.vsync` field exists but is unread; wire it up and expose via `AddBgfxRenderer` |
| 4 | TextureLoader moves from C# (ImageSharp) to C++ (stb_image) | Architecture principle: implementations in C/C++; C# is the wrapper layer only |
| 5 | Nodes belong in Framework, not Kernel | Already completed; Kernel contains only direct native wrappers |
| 6 | `.rsp` `--exclude` lists are a hack → replace with ClangSharp traversal config | Exclusion lists grow indefinitely; proper solution is scoped traversal |
| 7 | Shadow map creation is ke.render's responsibility, not the ECS system | GPU resource creation requires thread affinity to ke.render; systems run on ke.sim and must never call GPU APIs directly. `ShadowSystem::Update` previously violated this; fixed by removing GPU creation from `Update` and injecting the handle via `SetShadowMap` before the first frame |
| 8 | `ke_render*` must be removed from `ke_system_desc` (tracked, not yet done) | Holding a renderer pointer in the system descriptor is an API-level invitation to call GPU functions from ke.sim. Tracked in problem 1.22. Migration is one system at a time, ShadowSystem first |
| 9 | `simReady` ManualResetEventSlim is a temporary workaround, not a design | The correct fix (section 2.10) requires exposing semaphore handles from `ResourceCommandQueue` and `FrameSync` for `WaitHandle.WaitAny`. Workaround is acceptable until that infrastructure is built, but must not be extended to new use cases |
