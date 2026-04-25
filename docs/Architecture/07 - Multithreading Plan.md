# 07 — Multithreading Plan (Refactored)

## Philosophy

The kernel is a provider of **primitives and performance**. The high-level framework (C#, Python, etc.) is the **orchestrator (the glue)**. 

To ensure maximum performance and language agnosticism:
1.  **Core Systems** (Render, Physics, Animation) should be implemented in C/C++ to avoid Marshalling overhead and ensure they run at the same speed regardless of the framework language.
2.  **User Systems** can be implemented in the framework language for ease of use, with the Kernel providing the necessary "hooks" to include them in the global execution graph.
3.  **The Scheduler** lives in the Kernel. It doesn't care if a system is native or managed; it only cares about data dependencies (Component Access).

---

## Implemented state (Phases 1–3 complete)

```
ke.main (Main Thread):   bgfx API thread, SubmitPacket, Frame, PollEvents.
ke.sim  (KernelThread):   World.Update → Drives the System Graph.
Worker Pool (enkiTS):     Parallel execution of non-conflicting systems.
```

- `ke.main` owns the hardware context (bgfx).
- `ke.sim` drives the logic loop without touching the GPU directly.
- `FrameSync` handles the snapshot handoff between threads.
- **Phase 3 Success**: Systems now **record** snapshots into `ke_frame_packet`.

---

## Implementation phases

### Phase 1 — Threading Primitives ✅ DONE
- `ke_thread` and `ke_semaphore` C vtable contracts.
- C++ implementation using `std::thread`.

### Phase 2 — Frame Handoff ✅ DONE
- `ke_frame_packet` snapshot structure.
- `ke_frame_sync` double-buffer ring implementation.
- `Application.cs` thread split (Main vs Sim).

### Phase 3 — Record vs Submit ✅ DONE
- Render systems migrated to recording mode.
- `FrameSubmitter` (C++) added to process packets on the render thread.
- `Renderer.SubmitPacket` vtable slot wired.

### Phase 4 — Native System Graph (In Progress)
Migrate logic to low-level and implement the wave-based scheduler in C.

---

## Phase 4 — Native System Graph & ECS Parallelism

### Goal
Move the "Intelligence" of execution to the Kernel. Instead of the C# framework calling systems in a loop, it registers them in the Kernel, and the Kernel's `world_update` runs them in parallel waves via `enkiTS`.

### 1. The `ke_system` Contract (C)
Define a generic structure for systems in the Kernel.

```c
typedef void (*ke_system_update_func)(void* handle, struct ke_world* world, float dt, struct ke_frame_packet* packet);

typedef struct ke_system {
    void*                 handle;
    ke_system_update_func update;
    const char*           name;
    
    // Dependency Metadata
    const uint32_t*       reads;  uint32_t read_count;
    const uint32_t*       writes; uint32_t write_count;
} ke_system;
```

### 2. Implementation Steps

#### Step 4.1: Kernel System Registry (C)
- Update `world.h` to include `ke_world_add_system(world, system_desc)`.
- Implement internal system storage in `world.c`.

#### Step 4.2: Nativization of Render Systems (C++ Core)
- Move `MeshRenderSystem`, `LightRenderSystem`, etc. from C# to `src/cpp/render/core/`.
- Create a factory in the Render Assembly to return `ke_system` pointers to C#.
- **Result**: Logic runs at native speed, zero Marshalling per entity.

#### Step 4.3: Wave-Based Scheduler (C)
- Implement the "Wave Partitioning" algorithm in the Kernel.
- Systems that don't conflict (shared reads, different writes) are grouped into the same `SystemWave`.
- Systems with `writes == NULL` (like most render systems) are naturally parallel.

#### Step 4.4: Parallel Execution (C/C++)
- Update `ke_world_update` to iterate waves.
- For each wave with N > 1 systems: dispatch all to `ke_task_scheduler` and wait.
- This uses the existing enkiTS pool.

---

## Hybrid Support (Framework Vision)

The Kernel remains open to the "Language Glue":
- If the user writes a system in C#, the framework passes a `delegate* unmanaged` to the Kernel.
- The Kernel treats it exactly like a native system, just incurring the cost of one P/Invoke per frame (acceptable).
- This fulfills the vision of a "Plug-and-Play" architecture where performance-critical parts are native, but high-level logic is flexible.

---

## Thread Safety on Parallel Recording

To avoid locks when multiple systems fill the `ke_frame_packet` in parallel:
1.  **Read-only Data**: All systems read from the `ke_ecs_registry` simultaneously (Safe).
2.  **Draw Commands**: Use atomic increments for `packet->draw_count` OR pre-allocate slices for each parallel system in a wave.
3.  **Unique Outputs**: Systems that write to unique fields (Camera vs Lights) run in parallel safely. Systems that write to the same field are automatically serialized by the Wave Scheduler.
