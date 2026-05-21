# Multithreading

The kernel provides threading **primitives and performance**; it imposes **no threading model**. The 3-thread arrangement described here is a **framework decision** (`Application.cs`), chosen for a real-time game with a GLFW window and a bgfx renderer. A headless tool could run single-threaded; a server could use dozens. Nothing about the model is enforced by the kernel.

## Kernel primitives ✅

- **`ke_thread`** — named OS thread create/join.
- **`ke_semaphore`** — signal/wait.
- **`ke_frame_sync`** — a 2-slot double-buffer ring for producer/consumer handoff.
- **`ke_task_scheduler`** — parallel task scheduler contract (enkiTS backend), used for wave-based system execution and fork/join.

Implemented in C++ under `src/cpp/threading/` (`KeThread`, `KeSemaphore`, `KeFrameSync`) and `src/cpp/task_scheduler/enki/`.

## The framework's 3-thread model ✅

```
ke.main    — window/OS thread: GLFW PollEvents, Input.Update, InputBuffer.Produce, shutdown trigger.
ke.render  — renderer thread: Renderer.Initialize → loop(ResourceCommandQueue.Drain → SubmitPacket → Frame) → Dispose.
ke.sim     — simulation thread: World.Update (native script + transform systems) → OnUpdate → C# render systems → FrameSync producer.
Worker Pool (enkiTS) — parallel waves within World.Update, sub-tasks of ke.sim.
```

**Key principle**: the renderer does **not** manage its own threads. The framework creates `ke.render` and pins all GPU calls to it. This works identically for any backend (GL, D3D, Vulkan, bgfx) regardless of its internal threading.

### Startup sequence
1. `ke.main` creates the window (GLFW requires the main thread).
2. `ke.render` starts → `Renderer.Initialize()` → signals `renderReady`.
3. `ke.sim` waits on `renderReady` → calls `OnReady()` → enters the sim loop.
4. `ke.main` enters the event loop.

### Shutdown sequence
`ke.main` sets `_running = false` → a poison-pill write unblocks `ke.render` → worker threads join → `Renderer.Dispose()` runs on `ke.render` (same thread as `Initialize`).

## Cross-thread data channels

All thread-boundary data flows through explicit, typed contracts — never shared mutable state.

### `FrameSync` (ke.sim → ke.render) ✅
A 2-slot ring over `ke_frame_packet`. ke.sim calls `BeginWrite`/`EndWrite`; ke.render calls `BeginRead`/`EndRead`. Both block on semaphores when no slot is available. The frame packet is the **sole** sim→render channel: camera, lights, skybox, draw commands, post-fx settings.

### `InputBuffer` (ke.main → ke.sim) ✅
A lock-free single-slot exchange of `IInputReader` snapshots. ke.main produces; ke.sim consumes at the start of each `World.Update`. The sim reads a frozen, consistent input view for the whole frame.

### `ResourceCommandQueue` (ke.sim → ke.render) ✅
A `ConcurrentQueue` drained by ke.render at the top of each frame, before reading the frame packet. `ResourceCommandFactory` (the `IResourceFactory` impl) enqueues GPU-resource-creation commands and blocks ke.sim via `TaskCompletionSource<uint>` until ke.render returns the handle. The kernel provides the queue primitive; the blocking-vs-async **policy** is the framework's choice.

## Parallel system execution ✅

`World.Update` runs the system graph in **waves**. The kernel analyzes each system's declared `reads[]`/`writes[]` component access, groups non-conflicting systems into a wave, and dispatches the wave across the enkiTS worker pool. Systems writing the same component are serialized automatically.

Thread-safety of parallel recording:
- **Read-only ECS queries** — all systems read the registry concurrently (no writes), safe.
- **Draw command arrays** — `atomic_fetch_add` on `draw_count` / `shadow_draw_count` lets systems append in parallel without locks.
- **Disjoint packet fields** — camera, lights, skybox write separate fields, parallel by construction.

## Hybrid (C#) systems ✅

A C# system passes a `delegate* unmanaged` to the kernel and is scheduled alongside native systems. Cost is one P/Invoke per frame — acceptable for game logic, which is not per-entity. (Note: the built-in render systems are pure-managed C# invoked from `World.Update` after the native pass; see [07 - Graphics & Rendering](07%20-%20Graphics%20%26%20Rendering.md).)

## Thread-affinity safety ✅

Affinity violations are caught at runtime in debug builds: `ke_thread_assert_current` (C/C++) and `KernelThread.AssertCurrent(name)` (C#). E.g. `ResourceCommandQueue.Drain` asserts it runs on `ke.render`. The `[RequiresThread]` attribute documents affinity on managed members.

## Observability 📋

Frame/wave/system/draw-call timing is not yet visible. A **Tracy profiler** integration is planned (Kanban Phase N / Block 4) to expose the 3-thread timeline and per-wave system names. See [11 - Roadmap & Vision](11%20-%20Roadmap%20%26%20Vision.md).
