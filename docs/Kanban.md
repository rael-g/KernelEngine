# Engine Architecture Kanban

Technical roadmap for KernelEngine hardening, ECS refinement, and framework foundation.

---

## 📋 Todo

### Tier 1 — Verify & Stabilize (Current Focus)

#### [W.4] Layer Boundary Cleanup (Phase 2)
- **Why**: Prevent `EntryPointNotFoundException` and binding confusion. Enforce strict microkernel architecture where plugins only expose a factory.
- **What**: Move system factories from `bgfx_render.h` to internal headers or automate via C# metadata.
- **Acceptance**: `bgfx_render.h` contains only `ke_render_bgfx_create`. No `ke_system_params` factories in public plugin headers.
- **Steps**:
    1. Identify internal header for render system factories in `src/cpp/render/core`.
    2. Move factory declarations and implementations.
    3. Update C# bindings and Framework calls.

#### [Y.10] Bindings-drift Detection in CI
- **Why**: Prevent runtime crashes caused by P/Invoke signatures being out-of-sync with C headers (Bug 1.25).
- **What**: A CI script that compares modification times of headers vs generated files.
- **Acceptance**: Build fails if `src/c/kernel/include` or plugin public headers are newer than `Generated/*.cs`.
- **Steps**:
    1. Create `scripts/check_bindings_drift.py`.
    2. Add logic to find all `.h` and corresponding `.cs`.
    3. Add step to `.github/workflows/ci.yml`.

#### [Y.2] LogErr C++ Helper
- **Why**: Surface silent failures in native code that currently just return an error code.
- **What**: Macro/helper to log `__func__` and detail before returning `ke_result`.
- **Acceptance**: Every `return KE_ERROR_*` in BGFX plugin has a corresponding log entry.
- **Steps**:
    1. Define `LogErr` in `render_logging.hpp`.
    2. Audit `bgfx_gpu_device.cpp` and `core_renderer.cpp`.
    3. Replace bare returns with `return LogErr(...)`.

#### [Y.3] Debug Logging in Initialization
- **Why**: Identify why renderer fails to start (missing shaders, bad paths) without a debugger.
- **What**: Add trace-level logging for shader paths, file existence, and GPU capabilities.
- **Acceptance**: Log shows "load_shader('fs_basic'): OK" or "NOT FOUND" during startup.
- **Steps**:
    1. Instrument `BgfxGpuDevice::Init`.
    2. Add logging for each shader loaded.
    3. Log GPU vendor and renderer type from `bgfx::getCaps()`.

#### [Y.5] Audit Framework Result Discards
- **Why**: Detect operations that failed but were ignored (Bug 1.5 mitigation).
- **What**: Grep for `_ =` and unassigned result returns in `KernelEngine.Framework`.
- **Acceptance**: All critical paths call `ThrowIfFailed`.
- **Steps**:
    1. Scan Framework for `_ =` assignments.
    2. Replace with `KernelException.ThrowIfFailed`.
    3. Add comments for intentional discards.

#### [Z] Examples 06–13 Completion
- **Why**: E2E verification of implemented rendering features (Shadows, Clustered Lights, PostFX).
- **What**: Create runnable C# examples for every feature slice.
- **Acceptance**: All examples 01–13 run and show expected visuals.
- **Steps**:
    1. Implement 06 (Shadows).
    2. Implement 07–09 (Lights).
    3. Implement 10–13 (PostFX, SSAO, Assets).

#### [U.1] VSync Configuration
- **Why**: Allow performance benchmarking by uncapping framerate.
- **What**: Wire `WindowConfig.vsync` through to `bgfx::reset`.
- **Acceptance**: `vsync: false` produces FPS > monitor refresh rate.
- **Steps**:
    1. Update `BgfxGpuDevice` to read config.
    2. Update `AddBgfxRenderer` extension.
    3. Test with Example 01.

#### [L] Read/Write Set Enforcement (Debug)
- **Why**: Catch systems that violate their declared component access sets (Bug 1.13).
- **What**: Access log in `ke_ecs_registry` validated by the scheduler after each wave.
- **Acceptance**: System declaring `reads={A}` that calls `AddComponent(B)` triggers an assertion.
- **Steps**:
    1. Add `ke_access_record` to registry (debug-only).
    2. Instrument `component_get` and `component_add`.
    3. Add validation logic to `world_update` in the kernel.

### Tier 2 — Threading Hardening

#### [I] Entity Generations
- **Why**: Prevent silent corruption when using stale entity references (Bug 1.9).
- **What**: Change `ke_entity` to `{id, generation}` struct.
- **Acceptance**: Accessing a destroyed entity ID returns NULL/asserts instead of returning new entity data.
- **Steps**:
    1. Update `ke_entity` definition in C.
    2. Implement generation table in `ke_ecs_registry`.
    3. Update C# bindings and `Node` registry.

#### [J] Deferred Structural Mutations
- **Why**: Make `AddComponent`/`RemoveComponent` safe during parallel wave execution (Bug 1.10).
- **What**: Thread-local mutation buffers drained post-wave.
- **Acceptance**: Scripts can destroy entities during `OnUpdate` without corrupting the registry.
- **Steps**:
    1. Implement `ke_mutation_buffer` in C.
    2. Redirect registry writes to buffer during waves.
    3. Implement atomic drain in `world_update`.

#### [K] Node Registry Thread Safety
- **Why**: `s_registry` is a non-thread-safe Dictionary accessed from enkiTS workers (Bug 1.11).
- **What**: Switch to `ConcurrentDictionary` and add wave-active write guards.
- **Acceptance**: Parallel scripts calling `Scene.FindNode` do not crash.
- **Steps**:
    1. Update `Node.cs` to use `ConcurrentDictionary`.
    2. Add debug assertion for writes during waves.

#### [G] enkiTS CLR Thread Attachment
- **Why**: Ensure managed code in `ISystem` works correctly on native worker threads (Bug 1.4).
- **What**: Ensure `KernelThread` or enkiTS hooks attach worker threads to the CLR.
- **Acceptance**: `ISystem` updates can safely trigger GC and exceptions on any worker.
- **Steps**:
    1. Audit worker thread creation.
    2. Add `Thread.BeginThreadAffinity()` or relevant CLR attachment calls.

#### [N] Profiling & Trace Observability
- **Why**: Diagnose frame spikes and wave imbalances without guesswork (Bug 1.15).
- **What**: Per-thread ring buffer flushing to Chrome Trace JSON.
- **Acceptance**: Generating `ke_trace.json` showing 3 threads + workers timeline.
- **Steps**:
    1. Implement `ke_profile.h` macros.
    2. Add instrumentation to key engine milestones.
    3. Implement JSON exporter.

### Tier 3 — Fast Prototyping Base

#### [W.2] Composable Scene Format (.kscene)
- **Why**: Move away from hardcoded C# setups. Allow data-driven scene composition.
- **What**: JSON/Binary schema for node hierarchies and property serialization.
- **Acceptance**: Application can load a full level from a single file.
- **Steps**:
    1. Define `.kscene` schema.
    2. Implement `SceneAsset` loader.
    3. Update Examples to use files.

#### [SceneNode] Composable Prefabs
- **Why**: Allow nodes to reference other scene files as children, enabling complex hierarchies.
- **What**: `SceneNode` type that instantiates a sub-hierarchy from an asset.
- **Acceptance**: A "Player" node can be composed of "Body" and "Weapon" prefabs.
- **Steps**:
    1. Implement recursive instantiation logic.
    2. Handle property overrides on prefab instances.

### Tier 4 — Deferred / Optimization

#### [M] Frame Arena & Allocator Semantics
- **Why**: Eliminate heap allocations on the hot path (Bug 1.14).
- **What**: Bump-allocator reset per-frame for all transient data.
- **Acceptance**: Zero `malloc` calls in stable frame loop.
- **Steps**:
    1. Wire `ke_allocator_arena` to `FrameSync`.
    2. Update systems to use frame allocator.

#### [O] ABI Stability Strategy
- **Why**: Protect plugins from crashing when kernel structs change (Bug 1.17).
- **What**: `struct_size` guards and version constants.
- **Acceptance**: Plugin compiled against old kernel rejects loading or handles layout safely.
- **Steps**:
    1. Add `struct_size` to public structs.
    2. Add `ke_abi_check` to all API entries.

#### [P] Multi-Component ECS Queries
- **Why**: O(1) access for systems needing multiple components, eliminating O(n) lookups (Bug 1.18).
- **What**: `ke_ecs_query2/3` returning parallel arrays.
- **Acceptance**: Measurable speedup in `MeshRenderSystem` with high entity counts.
- **Steps**:
    1. Implement intersection algorithm in ECS.
    2. Update systems to use query2.

#### [Q] Managed Asset System
- **Why**: Proper resource lifecycle, reference counting, and deduplication (Bug 1.19).
- **What**: `AssetHandle<T>` and `AssetRegistry` with async loading support.
- **Acceptance**: Re-loading the same texture path returns existing handle; cleanup on zero refs.
- **Steps**:
    1. Implement `AssetRegistry` on C# side.
    2. Implement `AssetHandle` ref-counting.

#### [R] Error Context
- **Why**: Preserve file/line and diagnostic messages across C boundary (Bug 1.20).
- **What**: Thread-local `ke_error_context` with rich message support.
- **Acceptance**: `KernelException` message includes native file/line/detail.
- **Steps**:
    1. Implement TLS error storage in C.
    2. Update `ThrowIfFailed` to read context.

#### [S] Real Plugin Contract
- **Why**: Enable third-party renderer/window plugins without forking (Bug 1.21).
- **What**: `ke_plugin_register` entry point and runtime discovery.
- **Acceptance**: Engine loads `ke_render_vulkan.dll` via configuration.
- **Steps**:
    1. Implement `plugin_loader.c`.
    2. Refactor BGFX/GLFW to export register symbol.

#### [T.2] Screenshot Regression CI
- **Why**: Catch visual regressions automatically (Track T).
- **What**: Headless execution comparing PNGs against golden images.
- **Acceptance**: PR fails if a pixel diff exceeds threshold.

#### [X] Advanced Rendering Features
- **What**: Depth prepass (Early-Z), KTX2 textures, Offline asset pipeline.

---

## 🚧 In Progress

#### [W.5] Naming Convention Cleanup (Finalizing)
- **Why**: Standardize on `_params` to avoid confusion with graphics descriptors.
- **What**: Rename `_desc` -> `_params` engine-wide.
- **Acceptance**: No `_desc` suffixes remain in parameter bag structs.
- **Status**: C/C++ Done, C# Bindings Done, Framework Done. Cleanup of old files pending.

---

## ✅ Done

- [x] **[Y.4] Symbolic Result Names**: `KernelException` maps all `ke_result` codes.
- [x] **[W.4] Microkernel Hardening**: Moved TLS/Utilities from C++ plugin to C kernel.
- [x] **[P Wave 1] PAL Foundation**: `IDevPlatform` with Win32/Posix backends.
- [x] **[F] Structured Shutdown**: `join_timeout` + `CancellationTokenSource`.
- [x] **[H] MessagePipe Removal**: Dead code eliminated.
- [x] **[E] API Migration**: Examples 01–05 using `IResourceFactory`/`ISceneWriter`.
- [x] **[Y.1] bgfx Fatal Callback**: Captures file/line on abort.
- [x] **[Y.7-Y.9] Observability**: Log flush, SEH handler, Lifecycle logs.
- [x] **[B] Dead Code removal**: `GlfwWindow.cpp` deleted.
- [x] **[A] Handle Safety**: `UINT32_MAX` sentinel and typed handles.

---

## 📋 Tech Debt & Carry-Over
- [ ] Move SEH/Minidump code from `Application.cs` to `Win32DevPlatform` (Track P Wave 2).
- [ ] `EntryPointNotFoundException` (Bug 1.26): Symptom patched; verified via W.4 movement.
- [ ] **Bug 1.23**: Replace `simReady` spin-wait with `WaitHandle.WaitAny` on semaphores.
- [ ] **Bug 1.22**: Finalize removal of `ke_render*` from remaining system contexts.

---

## 🐞 Bug Catalog Mapping (Traceability)

This table ensures all defects from the original Problem Catalog (1.1–1.26) are tracked.

| Bug | Title / Category | Corresponding Kanban Card | Status |
|---|---|---|---|
| **1.1** | Sim-side Renderer Access | **[E] API Migration** | ✅ Done |
| **1.2** | Mutable Input State | **[D] Input Snapshot** | ✅ Done |
| **1.3** | Unsafe Shutdown | **[F] Structured Shutdown** | ✅ Done |
| **1.4** | enkiTS Workers as Unknown | **[G] enkiTS CLR Attachment** | 📋 Todo |
| **1.5** | Handle "None" Sentinel | **[A] Handle Safety** | ✅ Done |
| **1.6** | No Thread Enforcement | **[C] Thread Affinity** | ✅ Done |
| **1.7** | Dead code path (GlfwWindow) | **[B] Dead Code Removal** | ✅ Done |
| **1.8** | Dead `ke_message_pipe` | **[H] MessagePipe Removal** | ✅ Done |
| **1.9** | Stale Entity IDs | **[I] Entity Generations** | 📋 Todo |
| **1.10** | Structural ECS Races | **[J] Deferred Mutations** | 📋 Todo |
| **1.11** | Node Registry Race | **[K] Node Registry Safety** | 📋 Todo |
| **1.12** | Component Pointer Dangling | **[O] ABI Stability / [P] Queries** | 📋 Todo |
| **1.13** | Declared Set Violation | **[L] Read/Write Enforcement** | 📋 Todo |
| **1.14** | Frame Packet Overflow | **[M] Frame Arena / Capacity** | 📋 Todo |
| **1.15** | No Profiling/Visibility | **[N] Profiling & Trace** | 📋 Todo |
| **1.16** | Synchronous Resource Creation | **[Q] Managed Asset System** | 📋 Todo |
| **1.17** | No ABI Versioning | **[O] ABI Stability Strategy** | 📋 Todo |
| **1.18** | O(n) Multi-Comp Queries | **[P] Multi-Component Queries** | 📋 Todo |
| **1.19** | Ad-hoc Asset Lifecycle | **[Q] Managed Asset System** | 📋 Todo |
| **1.20** | Lost Error Context | **[R] Error Context** | 📋 Todo |
| **1.21** | Static Plugin Loading | **[S] Real Plugin Contract** | 📋 Todo |
| **1.22** | Renderer ptr in System | **Tech Debt: Bug 1.22** | 📋 Todo |
| **1.23** | OnReady Deadlock | **Tech Debt: Bug 1.23** | 📋 Todo |
| **1.24** | Thread Name Use-after-free | **[W.4] Microkernel Hardening** | ✅ Done |
| **1.25** | Binding Sync Out-of-date | **[Y.10] Bindings-drift CI** | 📋 Todo |
| **1.26** | EntryPointNotFound | **[W.4] Layer Boundary cleanup** | 🚧 In Progress |
