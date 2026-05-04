# 07 — Multithreading Plan

## Philosophy

The kernel is a provider of **primitives and performance**. The high-level framework (C#, Python, etc.) is the **orchestrator (the glue)**.

1. **Core Systems** (Render, Physics, Animation) run in C/C++ to avoid marshalling overhead per entity.
2. **User Systems** run in the framework language; the Kernel includes them in the global execution graph transparently.
3. **The Scheduler** lives in the Kernel. It only cares about data dependencies (component access), not the language of each system.

---

## Kernel vs Framework responsibility

**The kernel imposes no threading model.** It provides primitives — `ke_thread`, `ke_semaphore`, `ke_frame_sync` — that any implementation can use freely. A headless simulation could run on a single thread; a server could use dozens.

The 3-thread model described below is a **Framework decision** (`Application.cs`), chosen because it fits the use case of a real-time game with a GLFW window and a bgfx renderer. It is not the only valid model and it is not enforced by the kernel.

---

## Framework thread model (KernelEngine.Framework)

```
ke.main    — window/OS thread: GLFW PollEvents, Input snapshot, shutdown trigger.
ke.render  — renderer thread: Initialize → loop(ResourceQueue.Drain → SubmitPacket → Frame) → Shutdown.
ke.sim     — simulation thread: World.Update → drives the native System Graph → OnUpdate.
Worker Pool (enkiTS) — parallel waves within World.Update, sub-tasks of ke.sim.
```

**Key design principle**: the renderer does not manage its own threads. The Framework creates `ke.render` and pins all GPU calls to it. This works identically for any backend — OpenGL, DX11, Vulkan, bgfx — whether or not it has internal threading support.

**Startup sequence**:
1. `ke.main` creates the window (GLFW requires main thread).
2. `ke.render` starts → `Renderer.Initialize()` → signals `renderReady`.
3. `ke.sim` waits on `renderReady` → then calls `OnReady()` and enters the sim loop.
4. `ke.main` enters the event loop.

**Shutdown sequence**: `ke.main` sets `_running = false` → poison-pill write unblocks `ke.render` → both worker threads join → `Renderer.Dispose()` called from `ke.render` (same thread as `Initialize`).

> Note: `ke.main` previously also pumped a `MessagePipe`. That bus was removed (Phase H); input now travels via `ke_input_snapshot` through a lock-free exchange buffer.

---

## Implementation phases

### Phase 1 — Threading Primitives ✅
- `ke_thread` and `ke_semaphore` C vtable contracts.
- C++ implementation using `std::thread`.

### Phase 2 — Frame Handoff ✅
- `ke_frame_packet` snapshot structure.
- `ke_frame_sync` double-buffer ring: ke.sim writes, ke.render reads.
- `Application.cs` thread split.

### Phase 3 — Record vs Submit ✅
- Render systems record into `ke_frame_packet` (semantic level: handles, lights, camera).
- `FrameSubmitter` (C++) processes packets on `ke.render`, calls bgfx API.
- `Renderer.SubmitPacket` vtable slot wired.

### Phase 4 — Native System Graph ✅
- `ke_system_desc` contract in `world.h`: name, update, handle, reads[], writes[].
- Wave-based parallel scheduler in `world.c`: conflict analysis → `SystemWave[]` → enkiTS dispatch per wave.
- Render systems nativized in `src/cpp/render/core/`: MeshSystem, LightSystem, CameraSystem, ShadowSystem, SkyboxSystem.
- `BgfxSystemDescFactory` (C#, bgfx plugin layer) creates descriptors; Kernel layer stays unaware of bgfx.
- Managed `ISystem` wrappers are NO-OPs; execution happens at native speed in the Kernel.

### Phase 5 — Dedicated ke.render Thread ✅
- `ke.render` thread created by `Application`; renderer `Initialize`/`Dispose` called from this thread.
- `ke.main` reduced to window/OS events only.
- `ManualResetEvent renderReady` synchronizes ke.render init → ke.sim start.
- `RenderFrame()` API removed (no longer needed; bgfx runs single-thread on ke.render).

---

## Thread safety on parallel recording

- **Read-only ECS data**: all systems query the registry concurrently — safe (no writes).
- **Draw command arrays**: `atomic_fetch_add` on `packet->draw_count` / `packet->shadow_draw_count` allows parallel recording without locks.
- **Unique packet fields**: Camera, Lights, Skybox write to disjoint fields — parallel by construction.
- Systems writing to the same field are serialized automatically by the wave scheduler.

---

## Hybrid system support

User systems written in C# pass a `delegate* unmanaged` to the Kernel and are scheduled alongside native systems. The cost is one P/Invoke per frame — acceptable for game logic, which is not per-entity.
