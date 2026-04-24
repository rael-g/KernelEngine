# 07 — Multithreading Plan

## Philosophy

The kernel does not orchestrate anything. It provides **contracts and primitives** — the C# framework layer decides how to use them. This applies fully to multithreading: `ke_thread` is just a managed OS thread with a name. Whether it becomes a "render thread" or a "sim thread" is the framework's decision.

bgfx is the current render implementation. We do not want the threading model to be owned by bgfx. The framework creates the thread that bgfx will run on, passes it to bgfx, and controls its lifetime. If bgfx is replaced tomorrow, the threading infrastructure stays unchanged.

---

## Current state

```
Main Thread (C#):   bgfx::renderFrame() + window polling + input
Sim Thread (C#):    Task.Run → World.Update() + ISystem
Worker Pool:        enkiTS via ke_task_scheduler ✓
```

Problems:
- Threads created with C# `Thread`/`Task.Run` — no names, no affinity, no kernel visibility
- bgfx owns which thread it considers its "render thread" (the one that called `bgfx::init`)
- No decoupling between sim state and render submission — systems write directly to bgfx
- `Application.cs` is the orchestrator, but it does so with C# primitives that bypass the kernel

---

## Target state

```
Main Thread:    window polling + input (OS requirement on some platforms)
Render Thread:  created by framework via ke_thread, passed to bgfx as its home
Sim Thread:     created by framework via ke_thread, runs World.Update()
Worker Pool:    enkiTS (already ke_task_scheduler)
```

The framework (C#) controls all thread lifetimes. The kernel provides the primitives. bgfx adapts to which thread it is given.

---

## New C kernel primitives

### `ke_thread` — named OS thread

```c
// src/c/kernel/include/kernel_engine/kernel/threading/thread.h

typedef struct ke_thread ke_thread;

typedef void (*ke_thread_func)(void* user_data);

typedef struct ke_thread_desc {
    const char*     name;        // visible in profilers (RenderDoc, PIX, NSight, perf)
    ke_thread_func  func;
    void*           user_data;
    uint64_t        affinity_mask; // 0 = no preference
} ke_thread_desc;

ke_result ke_thread_create(ke_allocator* alloc, const ke_thread_desc* desc, ke_thread** out);
void      ke_thread_join(ke_thread* t);
void      ke_thread_destroy(ke_thread* t, ke_allocator* alloc);
void      ke_thread_set_name(const char* name);  // sets name on *calling* thread
```

### `ke_semaphore` — lightweight signal/wait

```c
// src/c/kernel/include/kernel_engine/kernel/threading/semaphore.h

typedef struct ke_semaphore ke_semaphore;

ke_result ke_semaphore_create(ke_allocator* alloc, uint32_t initial, ke_semaphore** out);
void      ke_semaphore_signal(ke_semaphore* s);
void      ke_semaphore_wait(ke_semaphore* s);
void      ke_semaphore_destroy(ke_semaphore* s, ke_allocator* alloc);
```

### `ke_frame_packet` — sim → render snapshot

The frame packet is the data written by the sim thread and consumed by the render thread. It replaces direct ECS-to-bgfx calls from within systems.

```c
// src/c/kernel/include/kernel_engine/kernel/threading/frame_packet.h

typedef struct ke_draw_command {
    uint32_t  mesh_handle;
    uint32_t  material_handle;
    ke_mat4   transform;
} ke_draw_command;

typedef struct ke_light_entry {
    ke_vec3   direction;
    ke_vec3   color;
    float     intensity;
} ke_light_entry;

typedef struct ke_camera_data {
    ke_mat4   view;
    ke_mat4   proj;
    bool      orthographic;
} ke_camera_data;

typedef struct ke_frame_packet {
    uint64_t         frame_number;
    ke_draw_command* draw_commands;
    uint32_t         draw_count;
    ke_light_entry*  lights;
    uint32_t         light_count;
    ke_camera_data   camera;
} ke_frame_packet;
```

### `ke_frame_sync` — double-buffer handoff

Coordinates ownership of frame packets between the sim thread (writer) and render thread (reader). Uses a double or triple buffer internally — no lock on the hot path, only a semaphore on the handoff point.

```c
// src/c/kernel/include/kernel_engine/kernel/threading/frame_sync.h

typedef struct ke_frame_sync ke_frame_sync;

ke_result        ke_frame_sync_create(ke_allocator* alloc, uint32_t buffer_count, ke_frame_sync** out);
ke_frame_packet* ke_frame_sync_begin_write(ke_frame_sync* fs);   // sim acquires writable buffer
void             ke_frame_sync_end_write(ke_frame_sync* fs);     // sim hands off to render
ke_frame_packet* ke_frame_sync_begin_read(ke_frame_sync* fs);    // render waits and acquires
void             ke_frame_sync_end_read(ke_frame_sync* fs);      // render releases buffer
void             ke_frame_sync_destroy(ke_frame_sync* fs, ke_allocator* alloc);
```

---

## C++ implementations

All primitives get a C++ implementation under `src/cpp/threading/`:

```
src/cpp/threading/
  CMakeLists.txt
  src/
    ke_thread_impl.cpp      // std::thread + platform SetThreadDescription / pthread_setname_np
    ke_semaphore_impl.cpp   // std::counting_semaphore (C++20) or platform equivalent
    ke_frame_sync_impl.cpp  // ring buffer of ke_frame_packet + two semaphores (write-ready, read-ready)
```

CMake target: `ke_threading` (shared library, follows same 4-tier pattern as render/window).

---

## C# managed wrappers

### `KernelThread`

```csharp
// src/csharp/KernelEngine.Kernel/KernelThread.cs
public sealed unsafe class KernelThread : IDisposable
{
    public static KernelThread Create(Allocator alloc, string name, Action func);
    public void Join();
    public void Dispose();
    // static: sets name on calling thread (useful for main thread)
    public static void SetCurrentName(string name);
}
```

### `KernelSemaphore`

```csharp
public sealed unsafe class KernelSemaphore : IDisposable
{
    public static KernelSemaphore Create(Allocator alloc, uint initial = 0);
    public void Signal();
    public void Wait();
    public void Dispose();
}
```

### `FrameSync` + `FramePacket`

```csharp
public sealed unsafe class FrameSync : IDisposable
{
    public static FrameSync Create(Allocator alloc, uint bufferCount = 2);
    public FramePacketWriter BeginWrite();   // returns ref-struct scoped to sim thread
    public FramePacketReader BeginRead();    // blocks until sim signals ready
    public void Dispose();
}
```

---

## How `Application` changes

Today `Application` uses `Thread` + `SemaphoreSlim`. After this work it becomes:

```csharp
protected override void Run()
{
    // Name the main thread via the kernel
    KernelThread.SetCurrentName("ke.main");

    var frameSync = FrameSync.Create(Allocator, bufferCount: 2);

    // Create the render thread — this thread will call bgfx::init
    var renderThread = KernelThread.Create(Allocator, "ke.render", () =>
    {
        Renderer.Initialize();   // bgfx::init happens here, on this thread
        while (!ShouldStop)
        {
            using var reader = frameSync.BeginRead();
            Renderer.SubmitFrame(reader.Packet);
            Renderer.Frame();           // bgfx::frame()
        }
    });

    // Create the sim thread
    var simThread = KernelThread.Create(Allocator, "ke.sim", () =>
    {
        OnReady();
        while (!ShouldStop)
        {
            using var writer = frameSync.BeginWrite();
            World.Update(writer.Packet);   // systems fill the packet
            OnUpdate();
        }
    });

    // Main thread: platform loop
    while (!Window.ShouldClose())
    {
        Window.PollEvents();
        Input.Update();
        MessagePipe.Pump();
        Renderer.RenderFrame();    // bgfx::renderFrame() — unblocks render thread
    }

    Stop();
    simThread.Join();
    renderThread.Join();
}
```

bgfx no longer decides its thread model. We create the thread, it happens to be the one bgfx runs on.

---

## Impact on existing render systems

Today `MeshRenderSystem.Update()` calls `renderer.SubmitMesh(...)` directly on the sim thread. After this work:

- Sim thread: systems **write** to `ke_frame_packet` (fill draw commands, lights, camera)
- Render thread: reads the packet and calls `renderer.SubmitMesh(...)` / bgfx API

This means `MeshRenderSystem`, `LightRenderSystem`, `CameraRenderSystem` etc. change from "submit" to "record". The actual GPU submission moves to a new internal `FrameSubmitter` that reads the packet.

---

## Implementation phases

### Phase 1 — `ke_thread` + `ke_semaphore` ✅ DONE
- C API headers in `src/cpp/threading/include/kernel_engine/threading/`
- C++ implementation `ke_threading.dll` (`std::thread` + platform thread naming/affinity)
- C# bindings generated via ClangSharp (`KernelEngine.Threading.Native`)
- `KernelThread` + `KernelSemaphore` managed wrappers in `KernelEngine.Kernel`
- `Application.Run` names main thread via `KernelThread.SetCurrentName("ke.main")`
- **No behavior change** — same logical threading model, just kernel-owned threads

### Phase 2 — `ke_frame_packet` + `ke_frame_sync` ✅ DONE
- Define `ke_frame_packet` struct in C kernel (`src/c/kernel/include/kernel_engine/kernel/engine/frame_packet.h`)
- C++ `ke_frame_sync` implementation — ring buffer + two counting semaphores (`src/cpp/threading/src/KeFrameSync.cpp`)
- C# bindings generated: `ke_draw_command`, `ke_frame_camera`, `ke_frame_shadow`, `ke_frame_packet`, `ke_frame_sync`
- `FrameSync` + `FramePacket` managed wrappers in `KernelEngine.Kernel`
- `Application` restructured: ke.sim owns bgfx::init + World.Update + Renderer.Frame; ke.main owns PollEvents + FrameSync consumer
- `Renderer.Initialize()` separated from constructor so ke.sim can be the bgfx API thread
- **Behavior change**: ke.sim and ke.main now run as separate KernelThreads; FrameSync provides double-buffered handoff (packets filled in Phase 3)

### Phase 3 — systems record instead of submit
- `MeshRenderSystem`, `LightRenderSystem`, `CameraRenderSystem` write to packet
- New `FrameSubmitter` reads packet on render thread and calls bgfx
- `ShadowRenderSystem`, post-process: TBD (may stay on render thread side)
- **This is the largest change** — touches every render system

### Phase 4 — internal ECS parallelism (future)
- `ke_world_update` schedules independent systems as enkiTS jobs
- Systems annotated with read/write component sets for dependency analysis
- Depends on Phase 3 being stable

---

## What does NOT change

- `ke_task_scheduler` (enkiTS) is the worker pool — unchanged
- The 4-tier modular architecture of render/window — unchanged
- C# is still the orchestrator of the frame loop — unchanged
- The kernel remains contract-only, no built-in threading policy

---

## Files to create / modify

```
NEW  src/c/kernel/include/kernel_engine/kernel/threading/thread.h
NEW  src/c/kernel/include/kernel_engine/kernel/threading/semaphore.h
NEW  src/c/kernel/include/kernel_engine/kernel/threading/frame_packet.h
NEW  src/c/kernel/include/kernel_engine/kernel/threading/frame_sync.h
NEW  src/cpp/threading/CMakeLists.txt
NEW  src/cpp/threading/src/ke_thread_impl.cpp
NEW  src/cpp/threading/src/ke_semaphore_impl.cpp
NEW  src/cpp/threading/src/ke_frame_sync_impl.cpp
NEW  src/csharp/Native/KernelEngine.Threading.Native/   (generated bindings)
NEW  src/csharp/KernelEngine.Kernel/KernelThread.cs
NEW  src/csharp/KernelEngine.Kernel/KernelSemaphore.cs
NEW  src/csharp/KernelEngine.Kernel/FrameSync.cs
MOD  src/csharp/KernelEngine.Framework/Application.cs
MOD  src/cpp/render/bgfx/src/bgfx_render_factory.cpp   (Phase 3)
MOD  src/csharp/KernelEngine.Framework/*RenderSystem.cs (Phase 3)
```
