# Engine Architecture — Design Rationale & Bug Catalog

> **What this document is**: design rationale, bug catalog, and architectural decisions.
> **What this document is NOT**: a status board. Active and pending work is tracked in [`docs/Kanban.md`](../Kanban.md).
>
> **For contributors**:
> - Working on a task? Find the card in `docs/Kanban.md`. The card links back here for design rationale.
> - Adding a new bug? Append to § 1 (Problem Catalog) and create a Kanban card pointing to the bug entry.
> - Making an architectural decision? Append to § 6 (Decisions Log).

Section index:
- § 1 — Problem Catalog (numbered bugs 1.1 to 1.52, with rationale and code references)
- § 2 — Target Architecture (design of where we want to be)
- § 3 — API Migration Summary (breaking-change guide for consumers)
- § 4 — Invariants (rules the architecture enforces by construction)
- § 5 — Risks & Open Questions (architectural decisions still pending)
- § 6 — Decisions Log (ADR-style record of locked decisions)

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

### 1.27 [HIGH] Plugin public header exports non-`_create` C function (`get_last_fatal_error`)

`src/cpp/render/bgfx/include/.../bgfx_render.h` declares `ke_render_bgfx_get_last_fatal_error()`
in addition to the legitimate `ke_render_bgfx_create()`. The microkernel rule (now codified in
CLAUDE.md and project memory) is that a plugin's public C-ABI header may declare ONLY its
`_create()` factory and tightly related types/structs. Any other C function exposed there
violates the contract.

The capability itself is universal — every rendering backend has a fatal-error path (Vulkan
`VkResult`, D3D `HRESULT`, Metal `NSError`, WebGPU error scopes). It belongs in the `ke_render`
vtable (kernel-level contract), not as a backend-specific symbol.

Today, `Application.cs:50` calls `KernelEngine.Render.Bgfx.Native.NativeMethods.render_bgfx_get_last_fatal_error()`
directly, hardcoding the Framework to bgfx. Switching backends would require rewriting that
call site.

**Tracked in**: Kanban W.7.

---

### 1.28 [HIGH] "system factory" pattern is misleading — not real factories

`src/cpp/render/bgfx/src/bgfx_system_factory.h` exports 5 functions named "factories"
(`ke_render_bgfx_create_mesh_system_params` etc.). They are NOT polymorphic factories like
the legitimate `ke_<plugin>_create()` (renderer/window/thread/...) — they don't return objects
with vtables. They just **fill a `ke_system_params` struct with function pointers**.

Three issues stack:
1. Same rule violation as 1.27 — plugins should expose only `_create()` C-wise.
2. The classes those "factories" instantiate (`MeshSystem`, etc.) are universal concepts
   (1.30), so naming them as bgfx-prefixed misrepresents ownership.
3. The "factory" naming is misleading — they aren't factories, they are struct-fillers that
   exist only because C# can't construct the function-pointer struct from outside.

**Decision (2026-05-08)**: eliminate the pattern entirely. Move system implementations to
pure C in the kernel (`src/c/kernel/src/render/systems/`). Systems use only `ke_render*`
vtable methods. Registration is done via `ke_*_system_register(world, deps)` — no struct
passed across language boundary. See Kanban W.9 for the full plan.

**Tracked in**: Kanban W.9.

---

### 1.29 [HIGH] C# Framework directly couples to `Bgfx.Native` bindings

The Framework layer (`KernelEngine.Framework`) is supposed to be backend-agnostic — it should
work with any `ke_render` implementation. But several call sites bypass the abstraction:

- `Application.cs:50` — calls `Bgfx.Native.NativeMethods.render_bgfx_get_last_fatal_error()`
- `Application.cs:286–291` — registers 5 systems via `BgfxSystemParamsFactory`
- `Application.cs:307` — error message hardcoded "AddBgfxRenderer"
- `ShadowRenderSystem.cs:3,25` — wrapper named "ShadowRenderSystem" (generic) calls
  `BgfxNative.render_bgfx_shadow_system_set_map`

A future DX12 or Vulkan-direct backend would require rewriting `Application.cs` and the 5
`*RenderSystem.cs` wrappers.

**Resolution**: emerges naturally from fixing 1.27 (W.7) and 1.28 (W.9).

---

### 1.30 [MEDIUM] Universal classes use namespace `kernel_engine::render::bgfx` instead of `::core`

All 14+ classes under `src/cpp/render/core/` (`MeshSystem`, `LightSystem`, `CameraSystem`,
`ShadowSystem`, `SkyboxSystem`, `ClusteredForward`, `CoreRenderer`, `FrameSubmitter`,
`PostProcessPipeline`, `ShadowPipeline`, `ShaderProvider`, `GeometryManager`, `LightingManager`,
`TextureManager`) use `namespace kernel_engine::render::bgfx`. They only call `ke_render*`
vtable methods — never bgfx-specific code. The namespace is a leftover from when `core` and
`bgfx` were the same library.

The misnomer tells future readers (and code-search tools) "this is bgfx code", when it isn't.
Confuses architectural intent. Mechanical fix.

**Tracked in**: Kanban W.8.

---

### 1.31 [MEDIUM] Internal-only headers placed in `include/` (8 files in render/core, 1 in shader_compiler)

8 of 10 `.hpp` files in `src/cpp/render/core/include/` are consumed only by `.cpp` files in the
same target (`ke_render_core`) — never cross-target. Per project rule, headers internal to one
target belong in `src/`. Putting them in `include/` wrongly suggests they are public plugin API
and exposes them to install paths and tooling unnecessarily.

The 8 internal-only files: `clustered_forward.hpp`, `frame_submitter.hpp`, `geometry_manager.hpp`,
`lighting_manager.hpp`, `post_process_pipeline.hpp`, `shader_provider.hpp`, `shadow_pipeline.hpp`,
`texture_manager.hpp`.

`core_renderer.hpp` and `native_systems.hpp` legitimately stay in `include/` — both consumed by
`bgfx_render_factory.cpp` (different target).

Additionally, `bgfx_shader_compiler.hh` exposes the entire `BgfxShaderCompiler` C++ class in its
public header. The class is only used by `bgfx_shader_compiler.cc` — should be a private `.hpp`
in `src/`.

**Tracked in**: Kanban W.6 (render/core) + W.10 (shader_compiler).

---

### 1.32 [HIGH] File extensions `.hh`/`.cc` violate documented convention

`ProjectGuidelines.md` mandates `.hpp`/`.cpp` for C++ and `.h`/`.c` for C. Three files violate:

| File | Should be |
|---|---|
| `src/cpp/render/bgfx_shader_compiler/include/.../bgfx_shader_compiler.hh` | `.h` (it's the C ABI public header) |
| `src/cpp/render/bgfx_shader_compiler/src/bgfx_shader_compiler.cc` | `.cpp` |
| `src/cpp/window/glfw/include/.../glfw_window.hh` | `.h` (C ABI public header) |

**Tracked in**: Kanban W.10 (shader_compiler) + W.11 (glfw).

---

### 1.33 [HIGH] Filenames use PascalCase instead of mandated snake_case

`ProjectGuidelines.md` says "Files MUST use snake_case". 16 files violate, all created early in
the project before the convention was enforced:

- `src/cpp/threading/src/`: `KeFrameSync.{cpp,hpp}`, `KeSemaphore.{cpp,hpp}`, `KeThread.{cpp,hpp}` (6)
- `src/cpp/asset/assimp/src/`: `AssimpConverter.{cpp,hpp}`, `AssimpLoader.{cpp,hpp}`,
  `InternalHelpers.hpp`, `TextureDecoder.{cpp,hpp}` (7)
- `src/cpp/task_scheduler/enki/src/`: `EnkiTaskScheduler.{cpp,hpp}` (2)

Mechanical rename via `git mv` to preserve history; update `target_sources` in CMakeLists and
`#include` paths.

**Tracked in**: Kanban W.12.

---

### 1.34 [HIGH] `using namespace` (forbidden by project guidelines) — 4 violations

`ProjectGuidelines.md`: "`using namespace` is strictly FORBIDDEN". Four violations:

- `src/cpp/render/bgfx/src/bgfx_render_factory.cpp:13` — `using namespace kernel_engine::render::bgfx`
- `src/cpp/asset/assimp/src/AssimpConverter.cpp:11` — `using namespace detail`
- `src/cpp/asset/assimp/src/AssimpLoader.cpp:17` — `using namespace detail`
- `src/cpp/asset/assimp/src/TextureDecoder.cpp:13` — `using namespace detail`

Replace with explicit `using X::specific_type` declarations or fully qualify usage.

**Tracked in**: Kanban W.13.

---

### 1.36 [MEDIUM] `KE_ID_<SERVICE>` macros declared but never used (cargo cult)

The kernel headers declare 8 service-id string macros: `KE_ID_RENDER`, `KE_ID_WINDOW`,
`KE_ID_INPUT`, `KE_ID_LOGGER`, `KE_ID_DEV_PLATFORM`, `KE_ID_SHADER_COMPILER`,
`KE_ID_ALLOCATOR_DEFAULT`, `KE_ID_ALLOCATOR_SCRATCH`. **Zero callers** in production code —
they only appear mirrored in auto-generated C# bindings as `ReadOnlySpan<byte>`.

Likely origin: an early "service registry by string ID" design that was never implemented.

**Recommendation**: delete all 8 macros. If a real plugin contract (Phase S) needs service IDs
later, redefine intentionally with a clear consumer.

### 1.37 [MEDIUM] Vtables expose internal pointers as public struct fields (`ke_input.allocator`, etc.)

`ke_input` (and possibly other vtable structs) declare `allocator` and `logger` as public
fields next to the function pointers:

```c
typedef struct ke_input {
    void *handle;
    struct ke_allocator *allocator;  // exposed but only used internally
    struct ke_logger *logger;        // idem
    void (*destroy)(struct ke_input *self);
    /* ... */
} ke_input;
```

These are implementation details — they live inside the impl pointed by `handle` and should
never be visible to consumers. Exposing them allows accidental coupling and breaks the
vtable abstraction (consumers might bypass the function pointers and access state directly).

**Recommendation**: remove `allocator` / `logger` from the public struct. Move them into the
internal impl reachable via `handle`. Audit other vtables for the same leak.

### 1.38 [LOW] `ke_console_sink_create` does not belong in kernel C

`src/c/kernel/include/.../logger/console_sink.h` declares `ke_console_sink_create` and the
implementation in `src/c/kernel/src/logger/console_sink.c` is a `printf` to stderr. This is
a concrete implementation, not a building block — violates the principle "kernel provides
building blocks, not built blocks".

**Recommendation**: move to either a new `KernelEngine.Logging.Console` C++ plugin (parallel
to existing `KernelEngine.Logging.Serilog`) or to the existing C# `ConsoleSink` only.
**Tracked in**: Kanban W.16.

### 1.40 [LOW] Hardcoded backend names in Framework error messages

`Application.cs:307` validates DI services with the message `"AddBgfxRenderer(shaderPath)"` —
hardcoded to bgfx. If we ever add a non-bgfx renderer, this message lies.

**Fix**: either generic message (`"AddXxxRenderer where Xxx is your renderer plugin"`) or
provide error message via the registration hook (each `AddXxxRenderer` registers its own hint
string).

**Tracked in**: Kanban W.14 (sub-item).

---

### 1.41 [HIGH] Render pipeline uses magic numbers extensively — bug-prone and unreadable

The render pipeline is filled with literal hex bitmasks and integer view IDs with no symbolic
names:

```cpp
ctx.gpu->SetState(0x0000000000000001ULL | 0x0000000000000008ULL, 0);  // WRITE_R | WRITE_A
ctx.gpu->Submit(1 /*SCENE*/, prog, 0, false);                         // view 1
ctx.gpu->SetViewClear(3, 0x0002, 0, 1.0f, 0);                         // view 3, DEPTH
```

This is unreadable, untypecheckable, and has caused at least one production-time bug:

**Concrete incident (2026-05-16)**: the tonemap fullscreen pass used `SetState(WRITE_R | WRITE_A)`
instead of `SetState(WRITE_RGBA)`. The G and B channels were dropped silently. Result: skybox
rendered only red components, mirror quad appeared black, ~1 hour of debug to triangulate via
shader-of-debug + state inspection. With named constants the bug would have been visible on
first read.

View IDs (0=shadow, 1=scene, 2=ssao, 3=brightpass, 4=blurH, 5=blurV, 6=tonemap) are spread
across `core_renderer.cpp`, `frame_submitter.cpp`, `texture_manager.cpp`, `shadow_pipeline.cpp`,
`post_process_pipeline.cpp` with no central enum. Renumbering or adding a view requires hunting
every magic literal across the codebase.

**Fix**: define `kStateWrite*`, `kStateDepthTest*`, `kStateBlend*`, `kStateCull*` constants and
a `View` enum in `src/cpp/render/contract/include/gpu_state.hpp` (or extend `gpu_types.hpp`).
Replace every magic number call site.

**Tracked in**: Kanban B4.2.

---

### 1.42 [MEDIUM] `dotnet run --no-build` silently uses stale native DLLs after `cmake --build`

After running `cmake --build --preset win` to recompile native code, `dotnet run --project ... --no-build`
does NOT re-deploy the freshly-built native DLLs to the example's `bin/Debug/net10.0/` folder.
The example launches with the *previous* `ke_render_core.dll` (or other native target). Symptoms
are subtle: code changes that should change runtime behavior appear to have no effect, leading
to wrong conclusions ("my fix didn't work, let me try another approach") when the fix actually
works but was never deployed.

**Concrete instances**:
- During tonemap debug (2026-05-16), DIAG fprintf statements added to `core_renderer.cpp` produced
  no output despite the file being recompiled. Cost: ~10 minutes investigating "why isn't my log
  appearing" before noticing deployed-DLL mtime was older than build-DLL mtime.
- The bug 1.25 follow-up rebuild had a similar incident.

**Fix**: either
- (a) drop `--no-build` from the standard workflow (force `dotnet build` every run, which propagates
  native DLLs via the existing `NativeDependencies.targets` mechanism); cost is ~3s extra per
  example launch
- (b) add a `scripts/run_example.py` (or PowerShell) helper that compares mtimes of
  `build/native/bin/ke_*.dll` against `examples/csharp/<X>/bin/Debug/net10.0/ke_*.dll` and copies
  the newer ones (with a warning) before launching
- (c) add a CI check that the deployed DLLs in each example bin folder are not older than the
  corresponding native lib

**Tracked in**: Kanban B1.5.

---

### 1.43 [HIGH] Managed wrappers and interfaces expose raw `ke_X*` pointers publicly

`KernelEngine.Kernel/` wrappers (`Renderer`, `Window`, `World`, `Allocator`, `Logger`, `Input`,
`DevPlatform`, `TaskScheduler`, `FramePacket`) all declare `public ke_X* Native { get; }` properties.
Two public interfaces, `IRenderer` and `IWindow`, even put the raw pointer in the contract:
`ke_render* Native { get; }`. This was justified as "needed for plugin DI extensions"
(see MEMORY.md / project notes), but the consequence is that:

- The framework layer (`KernelEngine.Framework/`) — and worse, **any consumer of the framework**
  (game/editor code) — can dereference unmanaged pointers, defeating the layered architecture.
- An interface like `IRenderer` is fundamentally a public contract; embedding `ke_render*` in it
  binds every alternate implementation (mocks, in-process tests, future backends) to the C ABI
  surface, which is the opposite of what an interface is supposed to abstract.
- Even legitimate cross-plugin wiring (e.g., `AddBgfxRenderer` needs the underlying `ke_render*`
  to fill the vtable) should happen via `internal` + `[InternalsVisibleTo("KernelEngine.Render.Bgfx")]`,
  not via `public`.

**Fix** (strong form — no leakage at all, not even `internal`):
- Make every `Native` pointer field **`private`** inside the wrapper class. Not `public`, not
  `internal`. The raw `ke_X*` must never escape the type that owns it.
- Remove `ke_X*` members from every public interface (`IRenderer`, `IWindow`, etc.).
- Every operation a *consumer* (framework, plugin, or game) needs to perform on the underlying
  native object becomes a method on the wrapper itself. Examples:
    - `KernelEngine.Render.Bgfx` no longer reads `renderer.Native` to wire its vtable; instead
      `Renderer` exposes a method like `AttachBackend(BgfxBackendParams params)` (or the bgfx
      plugin's `ke_render_bgfx_create` is called via a factory the wrapper itself owns).
    - `World.AddSystem(ke_system_params)` already takes a value type — no pointer needed.
    - Anything currently doing `world.Native->add_component(...)` becomes a method on `World`.
- `InternalsVisibleTo` between Kernel and plugin assemblies is also forbidden by this fix: if
  a plugin needs cross-assembly access, redesign the API so the wrapper itself exposes a typed
  managed method.
- Audit `KernelEngine.Framework`, plugin extensions, and `examples/csharp/**`: nothing should
  contain `unsafe` blocks or `ke_X*` dereferences except inside the owning wrapper.

**Acceptance**:
- `grep -rn "public.*ke_.*\\*\\s+Native" src/csharp/` → no matches.
- `grep -rn "internal.*ke_.*\\*\\s+Native" src/csharp/` → no matches.
- `grep -rn "unsafe" examples/csharp/` and `src/csharp/KernelEngine.Framework/` → no matches
  (or only inside well-justified, reviewed exceptions).
- A game written purely against `KernelEngine.Framework` cannot obtain or dereference a `ke_X*`.

**Tracked in**: Kanban B5.1 (Block 5 — API surface lockdown).

---

### 1.44 [HIGH] Plugin `render_core.h` exposes 6 public entry points (W.9 not eliminated, just moved)

The new `src/cpp/render/core/include/kernel_engine/render/core/render_core.h` declares six C entry
points: `register_default_systems` + 5 `*_describe` factories + `shadow_system_set_map`. W.9 was
supposed to **eliminate** the equivalent pattern (`bgfx_system_factory.h`); instead it was duplicated
into render_core, and `bgfx_render.h` retained the same 7 duplicates until cleaned up.

Public-API rules violated:
- Plugin should expose **one** create entry point only; system params factories are internals.
- Public C API for the engine lives in `src/c/kernel/include/`. Render.Core is a plugin, so its
  public header should be a single small file with the create entry point and nothing else.

**Status of `bgfx_render.h` half**: fixed in commit `9a87a37` (dead duplicates removed).

**Status of `render_core.h` half**: partial fix in commit `2ffbc3a` — the dead
`ke_render_core_register_default_systems` function (no callers) and its orphan
`ke_render_core_systems_params` struct were deleted.

**Resolution for remaining 6 entry points**: the 5 `*_describe` factories + `shadow_system_set_map`
are kept as the **extended public ABI** of the render_core plugin. Rationale: the C# wrapper
assembly (`KernelEngine.Render.Core`) consumes them to materialize managed wrappers
(`MeshRenderSystem`, etc.) that mirror the native systems. This isn't a "many factories like
W.9 cleaned up" smell — it's a coherent system-descriptor surface where each function returns
the same shape (`ke_system_params`) for one of N built-in render systems. The "one entry point
per plugin" rule is intended to prevent unrelated factories piling up, not to forbid a tight
group of mirror functions that share a single purpose.

**No further action** on this bug; rename or further consolidation would force a heavier
managed-side refactor with no clear win.

---

### 1.45 [HIGH] `KernelEngine.Framework` had direct dependency on `KernelEngine.Render.Bgfx` (FIXED)

`Application.cs` called `KernelEngine.Render.Bgfx.Native.NativeMethods.render_bgfx_get_last_fatal_error()`
directly, and `Framework.csproj` had a `ProjectReference` to `Render.Bgfx`. Framework must be
backend-agnostic.

**Status**: Fixed in commit `a97d9a8` — Framework now calls `IRenderer.GetLastFatalError()`
through the vtable; `Framework.csproj` no longer references `Render.Bgfx`.

---

### 1.46 [MEDIUM] `Asset.Assimp` plugin had reverse dependency on `Framework` (FIXED, with caveat)

`Asset.Assimp.csproj` referenced `Framework`, and `ModelHelper.cs` (inside Assimp) used Framework
types. A plugin must not know the Framework exists.

**Status**: Fixed in commit `37b95dd` — `ModelHelper.cs` moved to
`Framework/AssimpModelExtensions.cs`; `Asset.Assimp` no longer references Framework.

**Caveat / follow-up**: Framework now references `Asset.Assimp` directly. Correct direction, but
binds Framework to one asset loader. When a second loader appears, extract the helper into a bridge
assembly (`KernelEngine.Framework.Assimp` or similar) so consumers opt in.

---

### 1.47 [LOW] Examples 07–13 created without authorization, orphaned from solution (PARTIAL)

Junior agent created `examples/csharp/07_point_lights` through `13_full_scene` (7 projects) without
prior discussion or validation. None were in `KernelEngine.slnx`, so they never compiled in CI and
were never visually validated.

**Status**: Added to `KernelEngine.slnx` and confirmed compile (commit `2131aa2`). Visual validation
still pending — part of Kanban Block 3.

---

### 1.48 [LOW] `refactor_namespace.py` one-off script left in repo root (FIXED)

30-line search-and-replace used during the contract namespace migration; not deleted after use.

**Status**: Deleted in commit `2131aa2`.

---

### 1.49 [LOW] `*.csproj.lscache` files versioned (FIXED)

VS Code C# Dev Kit puts per-project language-service cache in the project folder when
`dotnet.projectsystem.cacheInProjectFolder: true`. Several files were committed by mistake.

**Status**: Fixed in commit `2131aa2` — `*.csproj.lscache` added to `.gitignore`; existing files
removed from index. Developers can also disable the source setting in their personal VS Code config.

---

### 1.50 [LOW] `gpu_device.hpp` mixes abstract contract and bgfx concrete implementation

`src/cpp/render/contract/include/gpu_device.hpp` declares both abstract `GpuDevice` (in
`kernel_engine::render`) and concrete `BgfxGpuDevice` (in `kernel_engine::render::bgfx`). Anyone
including the abstract contract drags the bgfx-specific header dependency.

**Fix**: split into `gpu_device.hpp` (abstract only) under contract, and `bgfx_gpu_device.hpp`
(concrete) under `src/cpp/render/bgfx_device/`.

**Tracked in**: Kanban B5.3.

---

### 1.51 [LOW] `ke_render_core` CMake target declares `cpp/render/contract/include` as PUBLIC include

`src/cpp/render/core/CMakeLists.txt` adds the contract include directory as PUBLIC, so any consumer
linking `ke_render_core` sees `gpu_device.hpp`, `gpu_types.hpp`, `render_logging.hpp` — internal
headers that aren't part of the public ABI.

**Fix**: change the include to `PRIVATE`.

**Tracked in**: Kanban B5.4.

---

### 1.52 [LOW] `ResourceFactoryExtensions` reaches into `ResourceCommandFactory.Queue` publicly

`ResourceFactoryExtensions.CreateMeshAsync` calls `rcf.Queue.Enqueue(...)`, requiring `.Queue` to
be `public`. The queue is an implementation detail of the async-handle dispatch.

**Fix**: add a `Task<uint> EnqueueAsync(ResourceCommandType, object)` method on
`ResourceCommandFactory`; extensions use it without touching `.Queue`. Make `Queue` private.

**Tracked in**: Kanban B5.5.

---

### 1.39 [LOW] Two-project per plugin (`KernelEngine.<X>.Native` + `KernelEngine.<X>`) is overengineering

Original intent was to keep auto-generated bindings in a separate project, expecting the
managed wrapper layer to grow. In practice, most wrapper projects contain just
`ServiceCollectionExtensions.cs` (one method). The split adds boilerplate without benefit.

**Recommendation**: consolidate into single project per plugin. Auto-generated bindings move
from `src/csharp/Native/KernelEngine.<X>.Native/Generated/` to
`src/csharp/KernelEngine.<X>/Native/`. Delete the `src/csharp/Native/` folder.

**Tracked in**: Kanban W.15.

---

### 1.35 [LOW] Misc naming/structure inconsistencies

Collected smaller items that don't deserve individual cards:

| Item | Issue |
|---|---|
| `KeTask.cs` | Inconsistent with `KernelThread`/`KernelException`/`KernelSemaphore`. Should be `KernelTask.cs` |
| `enki_task_scheduler_public.h` | Suffix `_public` is redundant — every header in `include/` is public by definition. Should be `enki_task_scheduler.h` |
| Threading exposes 3 separate headers (`thread.h`, `semaphore.h`, `frame_sync.h`) | Other plugins (bgfx, glfw, assimp, enki, dev_platform) expose a single header. Consider consolidating into `threading.h` |
| `_export.h` macro location | Inconsistent: `asset_export.h`, `render_export.h`, `window_export.h` at root of `include/`; `threading_export.h` nested inside `kernel_engine/threading/`. Pick one |
| `KE_API` macro used in `bgfx_shader_compiler.hh` | Should be plugin-specific `KE_SHADER_COMPILER_API`. Today it works only because `KE_API` is the kernel macro and reaches via include chain |

**Tracked in**: Kanban W.14.

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

## 3. API Migration Summary

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

## 4. Invariants This Architecture Enforces

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

## 5. Risks and Open Questions

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

## 6. Decisions Log

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
