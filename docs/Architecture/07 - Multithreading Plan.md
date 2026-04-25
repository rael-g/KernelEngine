# 07 — Multithreading Plan

## Philosophy

The kernel does not orchestrate anything. It provides **contracts and primitives** — the C# framework layer decides how to use them. This applies fully to multithreading: `ke_thread` is just a managed OS thread with a name. Whether it becomes a "render thread" or a "sim thread" is the framework's decision.

bgfx is the current render implementation. We do not want the threading model to be owned by bgfx. The framework creates the thread that bgfx will run on, passes it to bgfx, and controls its lifetime. If bgfx is replaced tomorrow, the threading infrastructure stays unchanged.

---

## Implemented state (Phases 1–3 complete)

```
ke.main (C# main thread):   bgfx::renderFrame() + window polling + input + SubmitPacket + Frame()
ke.sim  (KernelThread):     World.Update(packet) → ISystem records into FramePacket
Worker Pool:                enkiTS via ke_task_scheduler ✓
```

- `ke.main` is the bgfx API thread (called `bgfx::init`, owns all bgfx draw calls)
- `ke.sim` is a `KernelThread` (named, affinity-capable); runs pure simulation, no bgfx calls
- `FrameSync` (double-buffer ring) hands `ke_frame_packet` from ke.sim to ke.main each frame
- All render systems (`MeshRenderSystem`, `LightRenderSystem`, `CameraRenderSystem`, `SkyboxRenderSystem`, `ShadowRenderSystem`) **record** into the packet on ke.sim
- `FrameSubmitter` on ke.main reads the packet and issues all bgfx calls

---

## C kernel primitives (all implemented)

### `ke_thread` — named OS thread
```c
// src/c/kernel/include/kernel_engine/kernel/threading/thread.h
typedef struct ke_thread {
    void *handle;
    void (*destroy)(struct ke_thread *self, ke_allocator *alloc);
    void (*join)(struct ke_thread *self);
} ke_thread;

ke_result ke_thread_std_create(ke_allocator *alloc, const ke_thread_desc *desc, ke_thread **out);
void      ke_thread_set_current_name(const char *name);
```

### `ke_semaphore` — lightweight signal/wait
```c
// src/c/kernel/include/kernel_engine/kernel/threading/semaphore.h
typedef struct ke_semaphore {
    void *handle;
    void (*destroy)(struct ke_semaphore *self, ke_allocator *alloc);
    void (*signal)(struct ke_semaphore *self);
    void (*wait)(struct ke_semaphore *self);
} ke_semaphore;

ke_result ke_semaphore_std_create(ke_allocator *alloc, uint32_t initial, ke_semaphore **out);
```

### `ke_frame_packet` — sim → render snapshot
```c
// src/c/kernel/include/kernel_engine/kernel/engine/frame_packet.h
typedef struct ke_frame_packet {
    uint64_t         frame_number;
    ke_draw_command* draw_commands;       uint32_t draw_count;       uint32_t draw_capacity;
    ke_frame_shadow  shadow;
    ke_draw_command* shadow_draw_commands; uint32_t shadow_draw_count; uint32_t shadow_draw_capacity;
    ke_directional_light dir_light;       bool has_dir_light;
    ke_point_light*  point_lights;        uint32_t point_light_count; uint32_t point_light_capacity;
    ke_spot_light*   spot_lights;         uint32_t spot_light_count;  uint32_t spot_light_capacity;
    ke_frame_camera  camera;
    uint32_t         skybox_handle;       bool has_skybox;
} ke_frame_packet;
```

### `ke_frame_sync` — double-buffer handoff
```c
// src/c/kernel/include/kernel_engine/kernel/threading/frame_sync.h
typedef struct ke_frame_sync {
    void *handle;
    void (*destroy)(struct ke_frame_sync *self, ke_allocator *alloc);
    ke_frame_packet *(*begin_write)(struct ke_frame_sync *self);
    void             (*end_write)  (struct ke_frame_sync *self);
    ke_frame_packet *(*begin_read) (struct ke_frame_sync *self);
    void             (*end_read)   (struct ke_frame_sync *self);
} ke_frame_sync;

ke_result ke_frame_sync_std_create(ke_allocator *alloc, uint32_t buffer_count,
                                   uint32_t draw_capacity, uint32_t point_capacity,
                                   uint32_t spot_capacity, ke_frame_sync **out);
```

---

## Implementation phases

### Phase 1 — `ke_thread` + `ke_semaphore` ✅ DONE
- C kernel vtable headers + C++ `std::thread`/`std::counting_semaphore` implementations
- `ke_threading.dll` (shared library, 4-tier pattern)
- ClangSharp bindings → `KernelEngine.Threading.Native`
- `KernelThread` + `KernelSemaphore` managed wrappers
- `Application.Run` names main thread via `KernelThread.SetCurrentName("ke.main")`

### Phase 2 — `ke_frame_packet` + `ke_frame_sync` ✅ DONE
- `ke_frame_packet` in C kernel (`src/c/kernel/include/kernel_engine/kernel/engine/frame_packet.h`)
- `KeFrameSync` C++ implementation — ring buffer + two counting semaphores
- `FrameSync` + `FramePacket` managed wrappers in `KernelEngine.Kernel`
- `Application` restructured: ke.sim = `KernelThread`; ke.main = bgfx API thread
- `Renderer.Initialize()` on ke.main (bgfx::init ownership established)

### Phase 3 — systems record instead of submit ✅ DONE
- `MeshRenderSystem`, `LightRenderSystem`, `CameraRenderSystem`, `SkyboxRenderSystem`, `ShadowRenderSystem` — all record into `ke_frame_packet` on ke.sim
- `FrameSubmitter` on ke.main reads packet: lighting uniforms → shadow pass → scene pass → skybox
- `CoreRenderer::SubmitPacket` drives clustered light culling, SSAO, and post-process after scene
- `shadow_draw_commands` array added to `ke_frame_packet` for shadow casters

### Phase 4 — internal ECS parallelism
See detailed plan below.

---

## Phase 4 — Internal ECS Parallelism

### Goal

Each `ISystem` today runs sequentially on ke.sim. Systems that touch disjoint component sets are independent and can run as concurrent enkiTS jobs. Phase 4 introduces a **dependency-declared system graph** that the world schedules automatically.

The kernel does not know about scheduling policy — it only provides the contracts. The C# `World` wrapper builds the job graph and dispatches via `ke_task_scheduler`.

---

### New concept: system component access declaration

Systems declare which components they read and which they write. The scheduler uses this to build a dependency graph: two systems that share no write set and no read-write conflict run in parallel.

```csharp
// src/csharp/KernelEngine.Kernel/ISystem.cs  (extended)
public interface ISystem
{
    void Update(World world, float dt, FramePacket? packet = null);

    // Optional: override to declare component access for parallel scheduling.
    // Default = empty (treated as serial barrier).
    ComponentAccess GetAccess() => ComponentAccess.None;
}

public readonly struct ComponentAccess
{
    public IReadOnlyList<uint> Reads  { get; init; }
    public IReadOnlyList<uint> Writes { get; init; }

    public static readonly ComponentAccess None = new() { Reads = [], Writes = [] };
}
```

Systems that don't override `GetAccess` are treated as serial barriers (safe default, zero behavior change).

---

### Scheduling algorithm (C# side, `World.Update`)

```
1. Build groups: partition systems into waves where no two systems in the same wave conflict.
   Two systems conflict if:
     - either declares a write to a component the other reads or writes, OR
     - either has ComponentAccess.None (serial barrier — forces its own wave)

2. For each wave:
   a. If wave has 1 system → call Update() directly (no task overhead)
   b. If wave has N > 1 systems → dispatch N enkiTS tasks, wait for all to finish

3. Proceed to next wave.
```

Wave partitioning is computed once at startup (systems don't change at runtime) and cached as a `SystemWave[]`.

---

### New C# types

#### `SystemScheduler` (internal to `World`)

```csharp
// src/csharp/KernelEngine.Kernel/SystemScheduler.cs  (NEW, internal)
internal sealed class SystemScheduler
{
    // Called once after all AddSystem calls, before first Update.
    public void Build(IReadOnlyList<ISystem> systems);

    // Called each frame: dispatches waves via TaskScheduler.
    public void Run(World world, float dt, FramePacket? packet, TaskScheduler scheduler);

    // Exposed for tests.
    internal SystemWave[] Waves { get; private set; }
}

internal sealed class SystemWave
{
    public ISystem[]  Systems  { get; init; }
    public bool       Parallel { get; init; }   // false → run directly, no task dispatch
}
```

#### `TaskScheduler` C# wrapper (Phase 4 prerequisite)

`ke_task_scheduler` already exists in C (`src/c/kernel/include/kernel_engine/kernel/task_scheduler/task_scheduler.h`) and has a C++ enkiTS implementation. It's used by `AssetLoader` but has no C# managed wrapper yet.

```csharp
// src/csharp/KernelEngine.Kernel/TaskScheduler.cs  (NEW)
public sealed unsafe class TaskScheduler : IDisposable
{
    public static TaskScheduler Create(Allocator alloc, uint workerCount = 0);

    // Dispatches func as an enkiTS task. Returns a handle to wait on.
    public TaskHandle Dispatch(Action func);

    // Waits until all tasks in the handle set are complete.
    public void WaitAll(ReadOnlySpan<TaskHandle> handles);

    public void Dispose();
}
```

`TaskHandle` is a thin wrapper over `ke_task*`.

---

### Example: what runs in parallel today vs after Phase 4

```
Before Phase 4 (sequential):
  [ShadowRenderSystem] → [CameraRenderSystem] → [LightRenderSystem] → [MeshRenderSystem] → [SkyboxRenderSystem]

After Phase 4 (wave-scheduled):
  Wave 1 (parallel): [CameraRenderSystem W:Camera]  [LightRenderSystem W:Light]
  Wave 2 (serial):   [ShadowRenderSystem R:Light,Mesh]   ← needs light data from wave 1
  Wave 3 (parallel): [MeshRenderSystem R:Mesh]  [SkyboxRenderSystem]
```

Systems that the user writes and don't declare access remain serial (safe default).

---

### Built-in system access declarations

| System | Reads | Writes |
|---|---|---|
| `TransformSystem` (C, built-in) | Hierarchy | Transform |
| `ScriptSystem` (C, built-in) | Script | — |
| `CameraRenderSystem` | Transform | CameraComponent |
| `LightRenderSystem` | Transform | LightComponent |
| `MeshRenderSystem` | Transform, MeshComponent | — |
| `ShadowRenderSystem` | Transform, MeshComponent, LightComponent | — |
| `SkyboxRenderSystem` | — | — |

`TransformSystem` and `ScriptSystem` always run first in C (inside `ke_world::update`) — they are not affected by Phase 4 scheduling.

---

### Implementation steps

**Step 1 — `TaskScheduler` C# wrapper**
- Add `TaskScheduler.cs` + `TaskHandle.cs` to `KernelEngine.Kernel`
- Wire into DI: `AddTaskScheduler()` extension method
- `World` constructor accepts optional `TaskScheduler`

**Step 2 — `ComponentAccess` + `ISystem.GetAccess()`**
- Add `ComponentAccess` struct and extend `ISystem`
- Existing systems get `GetAccess()` overrides (table above)
- No behavior change — scheduler not yet used

**Step 3 — `SystemScheduler` (build + run)**
- Implement wave partitioning algorithm
- Single-system waves call `Update()` directly
- Multi-system waves: dispatch `N` enkiTS tasks, wait for all before next wave
- Unit test: verify wave partitioning for the known system set

**Step 4 — integrate into `World.Update`**
- Replace sequential `foreach (var sys in _systems)` with `SystemScheduler.Run(...)`
- `Application` passes `TaskScheduler` to `World`

**Step 5 — validate + examples**
- Existing examples must produce identical output
- Add a stress test: 1000 entities, 4 parallel MeshRenderSystem-like systems

---

### What does NOT change

- `ke_world::update` in C still runs `ScriptSystem` + `TransformSystem` sequentially (they mutate shared state)
- C# systems that touch ECS directly (read/write same component) remain serial by declaring overlapping write sets
- `FramePacket` append operations need thread-safety for parallel writes — use atomic `Interlocked.Increment` on `draw_count` or pre-assign each system a slice of the draw_commands array (preferred: slice assignment at wave build time, zero contention)
- Worker thread count comes from `TaskScheduler` (enkiTS manages the pool) — no new threads created

---

### Thread safety note on `FramePacket`

Parallel systems all write to the same `FramePacket`. The safe approach is **slice pre-assignment**: at wave-build time, each system in a parallel wave is assigned a fixed range `[start, start+capacity)` in `draw_commands`. Each system only writes to its slice. `draw_count` is set atomically after the wave completes. This avoids any lock on the hot path.

For lights and camera (single-writer per frame), parallel waves that write these fields must be in separate waves — enforced by the access declaration.
