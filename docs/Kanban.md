# Engine Architecture Kanban

Technical roadmap for KernelEngine hardening, ECS refinement, and framework foundation.

---

## ⚠️ Architectural Principles (read before adding cards)

1. **Public API lives ONLY in `src/c/kernel/include/`.** C++ plugins under `src/cpp/<plugin>/` expose exactly one public C function: `ke_<plugin>_create()`. All other headers in `<plugin>/include/` are for cross-target sharing within the plugin. Anything internal to one target goes in `src/`. *(Codified in CLAUDE.md.)*

2. **Kernel = building blocks, NEVER built blocks.** The kernel C provides primitives: ECS, vtable interfaces (`ke_render`, `ke_window`), allocator contract, logger contract. **It does not provide concrete systems, components, or implementations** — those grow infinitely with use cases and would bloat the kernel forever. Concrete systems live in higher-layer plugins (C++ or C#). The kernel cannot grow with every new feature.

3. **Universal-or-nothing for cross-cutting features.** When considering a new capability for the kernel: if it can be implemented on every shipping target (Windows, Linux, macOS, iOS, Android, WebGL, consoles), it can go in the kernel. If it is fundamentally platform-specific (SEH, minidump, OS thread name), it goes in a dev-only plugin (`KernelEngine.DevPlatform.*`). If it cannot be implemented somewhere we ship, we probably don't want it.

4. **No `malloc` directly.** Every component that allocates memory accepts an `ke_allocator*` via params. The user picks the allocator (malloc, arena, pool) per call site. There is no implicit global allocator.

5. **No "factory" naming for non-polymorphic functions.** A factory `_create()` returns a polymorphic object with vtable + lifecycle. A function that just fills a struct is NOT a factory — name it `_init`, `_describe`, `_register`, etc.

6. **Engine owns the contract; external libraries do the heavy lifting.** Every feature category has a universal vtable in the kernel and one or more backend plugins wrapping mature external libraries (bgfx for rendering, Jolt/Box2D for physics, miniaudio/FMOD for audio, ozz for animation, ENet/GNS for networking, ImGui/RmlUi for UI). Engineering effort goes into API design and integration — not into reinventing wheels. Exception: trivially small domains (e.g., `ConsoleSink`) where a wrapper is heavier than the impl. *(See `docs/EngineRoadmap.md` for per-domain library recommendations.)*

---

---

## 📋 Todo

### Tier 1 — Stabilization First (Current Focus)

> **Stabilization plan, locked 2026-05-08.** Coverage at 30.8% lines / 25.2% branches; render pipeline & threading at 0%; 94-commit branch never merged. Before alternating refactor/feature/bug/test work, we run **5 sequential blocks** to make the engine safe to evolve. Cards inside the same block can be parallelized; blocks must complete in order.
>
> Status will be tracked per block. Completing all 5 blocks is the gate to start M2/M3 features.

#### 🔧 BLOCK 1 — Close the long-lived branch (1–2 days)

##### [W.9] Eliminate `bgfx_system_factory.h` (unblock the branch)
*(Already detailed below. Pre-requisite for the rest of cleanup.)*

##### [B1.1] Final validation pass + merge `feat/multithread-architecture` to main
- **Tags**: `chore`
- **Why**: 94 commits, never merged. Main has not diverged (verified). Every new commit on the branch increases blast radius of eventual merge.
- **What**: Run full validation (build + ctests + dotnet test + example 05). On green, merge with `git merge --no-ff feat/multithread-architecture` from main.
- **Acceptance**: `main` HEAD includes the branch's 94 commits via a single merge commit. Branch can be deleted safely.
- **Steps**:
    1. Verify W.9 done; no pending bgfx_system_factory.h work.
    2. Run `cmake --build`, `ctest`, `dotnet test`, `dotnet run --project examples/csharp/05_skybox_ibl` — all must pass.
    3. `git checkout main && git merge --no-ff feat/multithread-architecture -m "Merge branch 'feat/multithread-architecture' (94 commits — multithread hardening, Phases A–F, Tracks Y/P, layer-boundary cleanup)"`
    4. Delete the branch locally and remote.
- **Effort**: S (half day if W.9 done).

##### [B1.5] Eliminate the `dotnet --no-build` stale-DLL trap
- **Tags**: `chore`, `bug` (Bug 1.42)
- **Why**: Running `dotnet run --no-build` after a native C++ rebuild silently uses the previously-deployed `.dll` in `bin/Debug/net10.0/` — the rebuild does NOT propagate. Symptoms: edited C++ code but example shows old behavior. Multiple agents (and the senior reviewer) have wasted debug cycles on this exactly.
- **What**: Either (a) drop `--no-build` from the standard run workflow (force `dotnet build` to copy fresh native DLLs), or (b) add a pre-run helper script that compares `build/native/bin/ke_*.dll` mtimes against the deployed copies in `examples/csharp/*/bin/Debug/net10.0/` and warns/copies on mismatch.
- **Acceptance**: Running the example after a `cmake --build` always picks up the latest native code without manual `dotnet build`. CI catches stale-deploy as an error.
- **Effort**: S (1–2 hours).

---

#### 🧪 BLOCK 2 — Test coverage where it hurts (3–5 days)

> Goal: lift coverage from 30.8% to **≥ 60%** in critical paths. Currently render/threading/Application = 0%. Any change to these is currently unsafe.

##### [B2.1] Unit tests for threading primitives (`KeThread`, `KeFrameSync`, `KeSemaphore`)
- **Tags**: `test`
- **Why**: 0% coverage today. Bug 1.24 (thread name use-after-free) shipped because no test guarded it.
- **What**: xUnit/gtest tests for thread create/join/timeout, semaphore signal/wait, frame_sync producer/consumer.
- **Acceptance**: ≥ 80% line coverage on `src/cpp/threading/src/`. Race-condition test harness for cross-thread scenarios.
- **Effort**: M (1–2 days).

##### [B2.2] Unit tests for `Application.cs` 3-thread orchestration
- **Tags**: `test`
- **Why**: Application is 5% covered. It's the most complex C# class (3 threads + DI + lifecycle). Bug 1.23 (deadlock) and Bug 1.26 (entry point) both ripple through it.
- **What**: Mock-based tests for thread startup ordering, simReady deadlock prevention, shutdown sequence, exception propagation.
- **Acceptance**: ≥ 60% line coverage on `Application.cs`. Tests prevent regression of Bugs 1.23 and 1.26.
- **Effort**: M (1–2 days).

##### [B2.3] Unit tests for cross-thread C# primitives (`SystemScheduler`, `ResourceCommandQueue`, `FrameSync`, `FramePacket`)
- **Tags**: `test`
- **Why**: All at 0–2% today. These are the data exchange spine between ke.sim/ke.render.
- **Acceptance**: ≥ 70% line coverage on each.
- **Effort**: M (1–2 days).

---

#### 🎨 BLOCK 3 — E2E examples 06–13 (3–5 days)

> Examples ARE the integration tests for render features. Without them, shadows/clustered lights/postFX could regress and we'd never know.

##### [B3.1] Example 06 — Shadow map verification
- **Tags**: `feat`, `test` (E2E)
- **Why**: Shadow map pipeline is implemented but unverified end-to-end. Last shadow regression took ~30min to diagnose.
- **What**: Scene with directional light + box + ground plane. Box casts shadow on ground.
- **Acceptance**: Visual: shadow visible, edges sharp, no z-fighting. Programmatic: golden-screenshot diff (Track T.2).
- **Effort**: S (half day).

##### [B3.2] Example 07–09 — Lights (point, spot, many)
- **Tags**: `feat`, `test` (E2E)
- **Acceptance**: Each runs at 60 FPS; correct illumination visible.
- **Effort**: M (1 day).

##### [B3.3] Example 10–11 — Post-FX (HDR/bloom, SSAO)
- **Tags**: `feat`, `test` (E2E)
- **Effort**: S (half day).

##### [B3.4] Example 12–13 — Asset loading + full scene
- **Tags**: `feat`, `test` (E2E)
- **Effort**: M (1 day).

---

#### 🔬 BLOCK 4 — Profiler + render observability (3–5 days)

##### [B4.1] Phase N — Tracy profiler integration
- **Tags**: `feat` (observability)
- **Why**: Without a profiler, debugging frame spikes / threading issues / wave imbalance still requires `printf`. Bug 1.23 took ~2 hours partly because there was no thread timeline view.
- **What**: Embed Tracy client in C/C++ + C#. Mark zones around frame, wave, system, draw call.
- **Acceptance**: Tracy connects to a running example, shows 3-thread timeline, system names visible per wave.
- **Effort**: M (1–2 days). Tracy is mature, integration is mostly include + zone macros.

##### [B4.2] Named constants for bgfx state bits + view IDs (replace magic numbers)
- **Tags**: `refactor`, `bug` (Bug 1.41)
- **Why**: Render code is full of `SetState(0x0000000000000001ULL | 0x0000000000000008ULL, 0)` and `Submit(1 /*SCENE*/, ...)`. Magic numbers are unreadable and silently wrong-by-typo. The visible-faces-only-red regression today was *literally* `WRITE_R | WRITE_A` instead of `WRITE_RGBA` — would have jumped off the page if it read `kStateWriteRA` vs `kStateWriteRGBA`. View IDs (0, 1, 2, 3, 6) are spread across `core_renderer.cpp`, `frame_submitter.cpp`, `texture_manager.cpp`, `shadow_pipeline.cpp`, `post_process_pipeline.cpp` with no central definition.
- **What**: Add named constants in `src/cpp/render/contract/include/gpu_types.hpp` (or new `gpu_state.hpp`):
    - `kStateWriteR`, `kStateWriteG`, `kStateWriteB`, `kStateWriteA`, `kStateWriteRGB`, `kStateWriteRGBA`
    - `kStateDepthTestLess`, `kStateDepthTestLEqual`, `kStateDepthWrite`
    - `kStateCullCw`, `kStateCullCcw`, `kStateMsaa`
    - `kStateBlendAlpha`, `kStateBlendAdditive`
    - View ID enum: `kViewShadow=0`, `kViewScene=1`, `kViewSsao=2`, `kViewBrightPass=3`, `kViewBlurH=4`, `kViewBlurV=5`, `kViewTonemap=6`
    - Replace every magic-number call site (sed-able, ~30 sites).
- **Acceptance**: `grep -nE 'SetState\(0x|Submit\(\s*[0-9]+\s*[,/]' src/cpp/render` returns nothing.
- **Effort**: S–M (half-day to a day, mechanical).

##### [B4.3] GPU framebuffer screenshot dump (debug-only)
- **Tags**: `feat` (observability)
- **Why**: When the rendered scene looks wrong, there's no way to see what each intermediate framebuffer contains (HDR FB, shadow map, bloom passes, SSAO buffer). Today's debug required substituting the tonemap shader with a fixed-color output to infer that "the tonemap quad never reached the screen". A 1-frame dump of all framebuffers as PNG would have shown immediately whether the HDR FB had the scene or not.
- **What**: Add `Renderer.DumpFramebuffer(handle, path)` to managed wrapper + bgfx `requestScreenShot` integration. Plus an `Application` debug hotkey (F12?) that dumps every named framebuffer (`hdr_fb`, `shadow_map_<id>`, `bright_fb`, `blur_a_fb`, `blur_b_fb`, `ssao_fb`) to `screenshots/` for the next frame.
- **Acceptance**: pressing F12 in any example produces a folder of PNGs, one per framebuffer, with descriptive names.
- **Effort**: S (half day). bgfx already supports screenshot capture; we just need to wire it.

##### [B4.4] Visual smoke test — golden-screenshot diff per example
- **Tags**: `test`, `feat`
- **Why**: "Tela branca", "tudo vermelho", "shadow disappeared", "post-process broke" — all classes of bug that take a human looking at the window to notice. Each one is a screenshot diff that CI can run. Without this, render regressions ship.
- **What**: For each `examples/csharp/0X_*/`, capture a reference frame (after a known-good run) → `examples/csharp/0X_*/golden.png`. In CI (or `python scripts/run_tests.py`), run each example headless for N seconds, capture frame, compare against golden with pixel-tolerance threshold. Fail if diff > 2%.
- **Acceptance**: CI fails when example 05 renders "all red and black" or "blank screen". Updating an intentional visual change requires regenerating the golden and committing it.
- **Effort**: M (1–2 days). Need: headless capture path (bgfx supports), image diff lib (`SixLabors.ImageSharp` already in deps), CI step.
- **Dependencies**: B4.3 (framebuffer dump) provides the capture mechanism.

---

#### 🧹 BLOCK 5 — Architectural cleanup (2–3 days)

> All the W.X cards already in this Kanban: W.6, W.7, W.8, W.10, W.11, W.12, W.13, W.14, W.15, W.16. Plus the remaining observability gaps Y.2, Y.3, Y.5. Plus B5.1 below.
>
> By doing these LAST in stabilization, we avoid mixing convention cleanup into critical bug-fixing periods.

##### [B5.1] Fully encapsulate native pointers inside wrappers — no `public`, no `internal` leakage (Bug 1.43)
- **Phase 1 status**: ✅ Done (commit `e1dde51`). All `Native` properties in `KernelEngine.Kernel` are now `internal`; `Native` removed from `IRenderer` and `IWindow` public interfaces; plugin assemblies access via `InternalsVisibleTo`.
- **Phase 2 plan** (locked 2026-05-18, Hexagonal/Ports-and-Adapters approach — user-approved):
  1. **Create `KernelEngine.Contracts` assembly** (new). Pure interfaces, ZERO `unsafe`, ZERO `Native` exposure: `IAllocator`, `ILogger`, `IWindow`, `IRenderer`, `IDevPlatform`, `IInput`, `ITaskScheduler`, `IFramePacket`, `IEcsRegistry`, `IWorld`, `ISystem`, `IFrameSync`, `IInputReader`, `ISceneWriter`, `IResourceFactory`, `ILoggerSink`. Plus the marker `IComponent`. Plus `Component<T>` wrapper struct.
  2. **Reverse phase 1**: re-expose `public Native` on Kernel wrappers; remove `InternalsVisibleTo` from `KernelEngine.Kernel.csproj` (keep only Tests).
  3. **`KernelEngine.Framework`** stops referencing `KernelEngine.Kernel`. References only `KernelEngine.Contracts`. All usages of concrete types (`Allocator`, `Logger`, etc.) become interface types. This breaks compilation of every `.Native` access in Framework — that's the point.
  4. **Plugin assemblies** (`Render.Bgfx`, `Window.Glfw`, `Asset.Assimp`, `TaskScheduler.Enki`, `DevPlatform.Win32`, `Logging.Serilog`) reference `KernelEngine.Kernel` directly (engine-internal). Their `Add*` extensions get concrete wrappers from DI (cast or `GetRequiredService<Window>()` not `<IWindow>()`) and access `.Native` freely. Return interfaces to DI.
  5. **Caso 1** (`Application.SetOsThreadName`): add `IDevPlatform.SetOsThreadName(string)` managed method. Concrete `DevPlatform` does the unsafe vtable call internally.
  6. **Caso 3** (FramePacket managed API): add methods to `IFramePacket` for all per-frame writes (`SetCamera`, `SetDirectionalLight`, `AddPointLight`, `RecordDraw`, etc.). Rewrite 5 render systems in Framework without `unsafe`. `Mat4` helper stays internal-to-Framework `unsafe` (acceptable — low-level math, doesn't leak).
  7. **Caso 8** (`AssetLoader`): inject `ITaskScheduler` via constructor; remove `.Native` access in `LoadModelAsync`.
  8. **Caso 2** (`Component<T>` wrapper for `Node.GetComponent`): **DEFERRED** — user-defined components/systems are deferred to the workflow layer; scriptable nodes will cover most cases.
- **Acceptance gate**:
    - `grep -rn "KernelEngine\\.Kernel" src/csharp/KernelEngine.Framework/*.csproj` → no matches.
    - `grep -rn "\\bunsafe\\b" src/csharp/KernelEngine.Framework/ examples/csharp/` → only `Framework/Internal/Mat4.cs`.
    - `grep -rn "InternalsVisibleTo" src/csharp/` → only `*.Tests` and the engine-internal `KernelEngine.Asset.Assimp` (if needed for ModelHelper).
    - All examples build green; ctest 179/179; dotnet test 80/80.
- **Effort**: L (touches a large fraction of C# but mechanical once Contracts assembly exists).

(original card text below for reference)

- **Tags**: `refactor`, `bug` (Bug 1.43)
- **Why**: `KernelEngine.Kernel` wrappers (`Renderer`, `Window`, `World`, `Allocator`, `Logger`, `Input`, `DevPlatform`, `TaskScheduler`, `FramePacket`) expose `public ke_X* Native { get; }`. Worse, public interfaces (`IRenderer`, `IWindow`) embed raw pointers in their contract. This defeats the layered architecture — the framework and (worse) the framework's users can dereference unmanaged memory. An interface that contains a `ke_render*` is binding all alternate implementations to the C ABI, which is the opposite of what an interface should do. **`internal` is not enough**: cross-assembly trust via `InternalsVisibleTo` still leaks the unmanaged surface across the layer line. The wrapper must own the pointer fully and expose only managed methods.
- **What**:
    1. Make every `Native` pointer field **`private`** inside the wrapper class. No `public`, no `internal`.
    2. Remove every `ke_X* Native` member from public interfaces.
    3. Every operation a consumer (framework, plugin, game) needs to perform on the underlying native object becomes a method on the wrapper. Plugin extensions like `AddBgfxRenderer` should call wrapper-owned factory methods, not reach in for the pointer.
    4. Forbid `[InternalsVisibleTo]` for native-pointer access between Kernel and plugins — if a plugin needs cross-assembly access, redesign so the wrapper exposes a typed managed method.
    5. Audit `KernelEngine.Framework`, plugin extension assemblies, and `examples/csharp/**`: no `unsafe` blocks or `ke_X*` dereferences should remain except inside the owning wrapper.
- **Acceptance**:
    - `grep -rn "public.*ke_.*\\*\\s+Native" src/csharp/` → no matches.
    - `grep -rn "internal.*ke_.*\\*\\s+Native" src/csharp/` → no matches.
    - `grep -rn "unsafe" examples/csharp/` and `src/csharp/KernelEngine.Framework/` → no matches (or only well-justified, reviewed exceptions).
    - A game written purely against `KernelEngine.Framework` cannot obtain or dereference a `ke_X*`.
- **Effort**: L (2–3 days). Interface changes ripple through plugin assemblies; some currently-public APIs will need redesign to remove pointer leaks.

##### [B5.2] Eliminate dup entry points in `render_core.h` (Bug 1.44) — RESOLVED
- **Tags**: `refactor`, `bug` (Bug 1.44)
- **Resolution** (commits `2ffbc3a`, `f98edc1`): the entire `render_core.h` public header was deleted along with the rest of the C++ render-systems infrastructure. The render systems were ported to pure-managed C# in `KernelEngine.Framework`, and the now-redundant `KernelEngine.Render.Core` C# wrapper assembly was deleted. `ke_render_core` C++ library survives only as an internal pipeline support lib (CoreRenderer, GeometryManager, etc.) consumed by bgfx via C++ headers; it has no public C ABI anymore.

##### [B5.3] Split `gpu_device.hpp` — separate abstract contract from bgfx concrete (Bug 1.50)
- **Tags**: `refactor`, `bug` (Bug 1.50)
- **Why**: Anyone including the abstract `GpuDevice` contract drags the concrete `BgfxGpuDevice` declaration via the same header.
- **What**: Keep `gpu_device.hpp` with the abstract class only. Move `BgfxGpuDevice` declaration into `bgfx_gpu_device.hpp` under `src/cpp/render/bgfx_device/`. Update includes in `bgfx_render_factory.cpp` and the device source.
- **Acceptance**: `gpu_device.hpp` has no `bgfx` mentions. `grep "BgfxGpuDevice" -r src/cpp/render/contract/` → no matches.
- **Effort**: S.

##### [B5.4] Make `ke_render_core` contract include PRIVATE (Bug 1.51)
- **Tags**: `chore`, `bug` (Bug 1.51)
- **Why**: PUBLIC include of `cpp/render/contract/include` leaks engine-internal headers to consumers.
- **What**: Change `target_include_directories(ke_render_core PUBLIC ...)` so the contract path is `PRIVATE`. Verify consumers (bgfx_device) still compile via their own contract include.
- **Acceptance**: A test consumer linking `ke_render_core` cannot `#include <gpu_device.hpp>` without explicit additional include path.
- **Effort**: XS.

##### [B5.5] Hide `ResourceCommandFactory.Queue`; expose `EnqueueAsync` instead (Bug 1.52)
- **Tags**: `refactor`, `bug` (Bug 1.52)
- **Why**: Extension method `ResourceFactoryExtensions.CreateMeshAsync` requires `Queue` public, leaking the dispatch mechanism.
- **What**: Add `internal Task<uint> EnqueueAsync(ResourceCommandType type, object data)` on `ResourceCommandFactory`. Update extensions to use it. Make `Queue` private.
- **Acceptance**: `grep "rcf.Queue" -r src/csharp/` → no matches. Extensions still functional.
- **Effort**: XS.

*Other cards listed individually below — execute in any order within the block.*

---

#### 🚦 Gate to leave Tier 1

After all 5 blocks complete:
- Coverage ≥ 60% in render/threading/Application
- All examples 01–13 pass
- Profiler operational
- All W.X cleanup done
- Branch merged to main

→ Then alternate `feat / refactor / bug / test` per the user's preferred cadence.

---

### Tier 1 — Cleanup cards (executed in BLOCK 5)

#### [W.4] Layer Boundary Cleanup (Phase 2) — ✅ Done (commit `9a87a37`)
- **Why**: Prevent `EntryPointNotFoundException` and binding confusion. Enforce strict microkernel architecture where plugins only expose a factory.
- **What**: Move system factories from `bgfx_render.h` to internal headers or automate via C# metadata.
- **Acceptance**: `bgfx_render.h` contains only `ke_render_bgfx_create`. No `ke_system_params` factories in public plugin headers.
- **Steps**:
    1. Identify internal header for render system factories in `src/cpp/render/core`.
    2. Move factory declarations and implementations.
    3. Update C# bindings and Framework calls.

#### [W.6] Move Internal-Only render/core Headers from `include/` to `src/` — ✅ Done (commit `2131aa2`)
- **Tags**: `refactor`
- **Why**: 8 of 10 `.hpp` files in `src/cpp/render/core/include/` are consumed only inside the same target (`ke_render_core`). Per project rule, headers internal to a single target belong in `src/`. Having them in `include/` wrongly suggests they are public plugin API and confuses tooling/install paths.
- **What**: Move internal `.hpp` files from `include/` to `src/`. Two headers stay in `include/` because they're consumed cross-target by `bgfx_render_factory.cpp`: `core_renderer.hpp`, `native_systems.hpp`.
- **Acceptance**: `find src/cpp/render/core/include -name '*.hpp'` lists only `core_renderer.hpp` and `native_systems.hpp`. Build passes; no external consumer breaks.
- **Steps**:
    1. Move 8 files: `clustered_forward.hpp`, `frame_submitter.hpp`, `geometry_manager.hpp`, `lighting_manager.hpp`, `post_process_pipeline.hpp`, `shader_provider.hpp`, `shadow_pipeline.hpp`, `texture_manager.hpp` → `src/cpp/render/core/src/`
    2. **Caveat**: `core_renderer.hpp` (which stays in `include/`) currently includes 6 of these. Refactor to use forward declarations + PIMPL idiom OR `unique_ptr<Impl>` so the public class header doesn't need to see the internal types.
    3. Update `#include` paths in all `.cpp` files (relative paths now).
    4. Build + run example 05 to verify.

#### [W.7] Move `get_last_fatal_error` from bgfx Plugin to `ke_render` Vtable — ✅ Done (commits `2131aa2`, `a97d9a8`, `9a87a37`)
- **Tags**: `refactor`, `bug` (Bug 1.27)
- **Why**: `bgfx_render.h` exposes `ke_render_bgfx_get_last_fatal_error()` — a non-`_create` C function in a plugin's public header. Direct violation of the "plugin exposes only `_create`" rule. Application.cs calls this directly, coupling the generic Framework to bgfx. The capability (retrieving last error message) is universal — every backend has it (Vulkan, D3D, Metal, etc.). Belongs in the `ke_render` vtable, not in a backend-specific header.
- **What**: Add `const char* (*get_last_fatal_error)(struct ke_render*)` to `ke_render` vtable. Each backend implements it. Remove `ke_render_bgfx_get_last_fatal_error` from `bgfx_render.h`. Update `Renderer.cs` wrapper. Update `Application.cs` to call via wrapper instead of via `Bgfx.Native`.
- **Acceptance**: `bgfx_render.h` only exports `ke_render_bgfx_create`. `Application.cs` has zero references to `KernelEngine.Render.Bgfx.Native`.
- **Steps**:
    1. Add `get_last_fatal_error` to `ke_render` struct in `src/c/kernel/include/.../render/render.h`.
    2. Implement in `core_renderer.cpp` (delegating to existing `GetLastFatalError()`).
    3. Wrap in `Renderer.cs` as `Renderer.GetLastFatalError() : string?`.
    4. Update `Application.GetGpuFatalError()` to use `Renderer.GetLastFatalError()`.
    5. Remove function from `bgfx_render.h` + `bgfx_render_factory.cpp`.
    6. Regenerate bindings; build + test.

#### [W.8] Rename Namespace `kernel_engine::render::bgfx` → `kernel_engine::render::core` for `render/core/` Files — ✅ Done (commit `2131aa2`)
- **Tags**: `refactor`, `bug` (Bug 1.30)
- **Why**: All 10 `.hpp`/`.cpp` files under `src/cpp/render/core/` use namespace `kernel_engine::render::bgfx`. This is a leftover from the early days when `core` and `bgfx` were the same library. These classes (`MeshSystem`, `LightSystem`, `CameraSystem`, `ShadowSystem`, `SkyboxSystem`, `ClusteredForward`, `CoreRenderer`, `FrameSubmitter`, `PostProcessPipeline`, `ShadowPipeline`, `ShaderProvider`, `GeometryManager`, `LightingManager`, `TextureManager`) are conceptually universal — they only call `ke_render*` vtable methods, never bgfx-specific code. The namespace is misleading and tells future readers "this is bgfx code" when it isn't.
- **What**: Replace `namespace kernel_engine::render::bgfx` with `namespace kernel_engine::render::core` in every file under `src/cpp/render/core/`. Update `using namespace` and qualified references in `bgfx_render_factory.cpp` accordingly.
- **Acceptance**: `grep -rln 'kernel_engine::render::bgfx' src/cpp/render/core/` returns nothing. Build passes; example 05 runs.
- **Steps**:
    1. Mechanical sed across `src/cpp/render/core/` files.
    2. Update `bgfx_render_factory.cpp` (which uses `kernel_engine::render::bgfx::CoreRenderer` etc.) to use the new namespace.
    3. Same for any other consumer (verify with grep).
    4. Build + test.

*Note*: Files truly bgfx-specific (`BgfxGpuDevice` in `src/cpp/render/bgfx_device/`) keep `kernel_engine::render::bgfx` — that's correct.

#### [W.9] Promote `render/core` to Standalone Agnostic Plugin — Eliminate "system factory" Pattern
- **Status**: ✅ Done
- **Tags**: `refactor`, `bug` (Bug 1.28, 1.29)
- **Why**: `bgfx_system_factory.h` exports 5 functions called "factories" — they are NOT polymorphic factories like the legitimate `ke_<plugin>_create()`. They just fill a `ke_system_params` struct with function pointers. Misleading naming; violates "plugin exposes only `_create`"; names them `ke_render_bgfx_*` when underlying classes are universal.
- **Architectural principle (locked 2026-05-08)**: **Kernel C = building blocks, never built blocks.** Components and systems can grow infinitely; the kernel cannot grow with them. Therefore systems do NOT belong in the kernel — they belong in a higher layer (C++ above kernel, or C#). The kernel exposes only the ECS + vtable interfaces (`ke_world`, `ke_render`); backends implement the vtable; systems live above and consume the vtable.
- **What**: Promote `src/cpp/render/core/` from "static sublib of bgfx plugin" to a standalone shared-lib plugin (`KernelEngine.Render.Core`). It exports a single `_create`-style entry point that bundles default render systems registered into a world. The bgfx plugin becomes purely a `ke_render` vtable implementation. Framework C# uses `KernelEngine.Render.Core` for system registration, never `Bgfx.Native`.
- **Acceptance**: `bgfx_system_factory.h` deleted. Zero "factory" functions for non-polymorphic things. `render/core` exports one C entry point that takes a `world*` + `ke_render*` and registers the default systems. Adding a new backend = implement `ke_render` vtable + reuse `render/core` unchanged.
- **Steps**:
    1. Convert `ke_render_core` from STATIC to SHARED library; expose a single public header in `src/cpp/render/core/include/kernel_engine/render/core/render_core.h` with one C function: `ke_render_core_register_default_systems(ke_world* world, ke_render* renderer, /* dependencies struct */)`.
    2. Move all classes from namespace `kernel_engine::render::bgfx` to `kernel_engine::render::core` (W.8 already plans this).
    3. Move internal-only `.hpp` files from `core/include/` to `core/src/` (W.6 already plans this).
    4. Delete `bgfx_system_factory.h` from bgfx plugin.
    5. Delete `BgfxSystemParamsFactory.cs`; create thin C# wrapper for the new `_register_default_systems` function.
    6. Update `Application.cs` to call `Renderer.RegisterDefaultSystems(world, ...)` or equivalent.
    7. Validate with example 05.
- **Effort**: L (3–5 days). Subsumes W.6 + W.8 partially.
- **Side benefit**: Eliminates A.1, A.2, A.4, A.5; cleans namespace; removes coupling Framework→Bgfx.Native.

*Decision rationale*:
- ~~Option A: Rename + expose from internal lib~~ — keeps misleading "factory" naming.
- ~~Option B: C wrapper functions in kernel pointing to C++ classes~~ — partial fix; kernel still grows.
- ~~Option 3a: Move systems to pure C in kernel~~ — **rejected**: violates "kernel = building blocks". Kernel cannot host every possible system.
- ~~Option 3b (locked 2026-05-08)~~: Promote `render/core` to standalone agnostic plugin. **Superseded** — the resulting plugin still leaked a public C ABI (6 entry points) and required a redundant C# wrapper assembly.
- ✅ **Option 3c (locked 2026-05-17)**: Move the 5 render systems to **pure C# in `KernelEngine.Framework`**. The C++ `render/core` library survives only as an internal pipeline support lib (CoreRenderer, GeometryManager, etc.) consumed by bgfx; it no longer has any public ABI. `KernelEngine.Render.Core` C# assembly deleted entirely. Render-specific component structs (`ke_light_component`, `ke_mesh_component`, etc.) deleted from kernel C — they live in C# only.
- **Migration commits**: `79990a1` (Camera), `49b8f1c` (Light), `3febc79` (Mesh), `4e7d841` (Skybox), `c3fbe66` (Shadow + Mat4 helper), `f98edc1` (delete dead C++/C/assembly).

#### [W.10] Audit `bgfx_shader_compiler` Plugin (Class in Public Header + Wrong Extensions) — ✅ Done (commits `e953bcc`, `b41bf88`)
- **Tags**: `refactor`, `bug` (Bug 1.31, partial 1.33)
- **Why**: `bgfx_shader_compiler.hh` exposes the entire `BgfxShaderCompiler` C++ class in the public header — a class that is only used internally by `bgfx_shader_compiler.cc`. Plus extensions are `.hh`/`.cc` instead of `.hpp`/`.cpp` (violates documented convention). Plus uses generic `KE_API` macro instead of plugin-specific `KE_SHADER_COMPILER_API`.
- **What**: Move `BgfxShaderCompiler` class declaration to a private `.hpp` next to the `.cpp`. Public header keeps only `ke_shader_compiler_bgfx_create`. Rename `.hh` → `.hpp`, `.cc` → `.cpp`. Define proper plugin-specific export macro.
- **Acceptance**: `bgfx_shader_compiler.h` (note `.h` for the C ABI public file) contains only `_create` declaration + `_params` struct. `BgfxShaderCompiler` class lives in `src/`.
- **Steps**:
    1. Rename files: `.hh` → `.h` (public, C ABI), `.cc` → `.cpp`.
    2. Extract `BgfxShaderCompiler` class to `src/cpp/render/bgfx_shader_compiler/src/bgfx_shader_compiler.hpp`.
    3. Define `KE_SHADER_COMPILER_API` export macro (own export header).
    4. Update CMakeLists `target_sources` for new file names.
    5. Build + test.

#### [W.11] Fix File Extensions (`.hh` → `.hpp`, `.cc` → `.cpp`) — ✅ Done (commit `e953bcc`)
- **Tags**: `chore`
- **Why**: `ProjectGuidelines.md` mandates `.hpp`/`.cpp` for C++ and `.h`/`.c` for C. Three files violate: `bgfx_shader_compiler.hh`, `bgfx_shader_compiler.cc`, `glfw_window.hh` (this last one is C ABI public — should be `.h`).
- **What**: Rename the 3 files; update CMakeLists, includes, and any other reference.
- **Acceptance**: `find src -name '*.hh' -o -name '*.cc'` returns nothing.
- **Steps**:
    1. `git mv` the 3 files to correct extensions.
    2. Search-and-replace `#include` references.
    3. Update `target_sources` in affected CMakeLists.
    4. Update `.rsp` files for bindings.
    5. Build + test.

*Note*: Items 1–4 of this card may already be subsumed by W.10 (shader_compiler) — keep this card focused on `glfw_window.hh` if W.10 lands first.

#### [W.12] Rename PascalCase Filenames to snake_case (16 files) — ✅ Done (commit `a3f9e0d`)
- **Tags**: `chore`
- **Why**: `ProjectGuidelines.md` says "Files MUST use snake_case". 16 files violate, all created early in the project before convention was enforced.
- **What**: Rename to snake_case. Examples: `KeThread.cpp` → `ke_thread.cpp`, `AssimpLoader.hpp` → `assimp_loader.hpp`, `EnkiTaskScheduler.cpp` → `enki_task_scheduler.cpp`.
- **Acceptance**: `find src/cpp src/c -type f \( -name '*.cpp' -o -name '*.hpp' -o -name '*.h' -o -name '*.c' \) | grep -E '/[A-Z]'` returns nothing.
- **Steps**:
    1. Files in threading: `KeFrameSync.{cpp,hpp}`, `KeSemaphore.{cpp,hpp}`, `KeThread.{cpp,hpp}` (6 files).
    2. Files in assimp: `AssimpConverter.{cpp,hpp}`, `AssimpLoader.{cpp,hpp}`, `InternalHelpers.hpp`, `TextureDecoder.{cpp,hpp}` (7 files).
    3. Files in enki: `EnkiTaskScheduler.{cpp,hpp}` (2 files).
    4. Use `git mv` to preserve history. Update CMakeLists. Update `#include`.
    5. Build + test.

#### [W.13] Remove `using namespace` Violations (4 files) — ✅ Done (no remaining occurrences in src/cpp or src/c headers)
- **Tags**: `refactor`
- **Why**: `ProjectGuidelines.md` says `using namespace` is "strictly FORBIDDEN". 4 files violate the rule, polluting global scope and risking name collisions.
- **What**: Replace `using namespace X` with explicit `using X::specific_type` declarations OR fully qualify the usage.
- **Acceptance**: `grep -rn '^using namespace ' src/cpp src/c --include='*.cpp' --include='*.hpp' --include='*.h'` returns nothing.
- **Steps**:
    1. `bgfx_render_factory.cpp:13` — replace `using namespace kernel_engine::render::bgfx` with explicit `using` decls.
    2. `AssimpConverter.cpp:11`, `AssimpLoader.cpp:17`, `TextureDecoder.cpp:13` — same for `using namespace detail`.
    3. Build + test (no behavior change expected).

#### [W.15] Eliminate `src/csharp/Native/` Folder — Single Project per Plugin — ✅ Done (commit `2131aa2`)
- **Status**: ✅ Done
- **Tags**: `refactor`
- **Why**: Today every plugin has 2 C# projects: `KernelEngine.<X>.Native` (bindings) + `KernelEngine.<X>` (managed wrapper + DI extension). Original intent was to keep auto-generated bindings isolated, expecting the wrapper layer to grow significantly. In practice, most wrapper projects contain only `ServiceCollectionExtensions.cs` (one method). The 2-project split is overengineering and adds boilerplate (.csproj, references, namespaces) for no benefit.
- **What**: Consolidate into single project per plugin. Move auto-generated bindings from `src/csharp/Native/KernelEngine.<X>.Native/Generated/` to `src/csharp/KernelEngine.<X>/Native/`. Delete the `src/csharp/Native/` folder. Update `.rsp`, `.csproj`, `.slnx`, and any references.
- **Acceptance**: `src/csharp/Native/` does not exist. Each plugin lives in `src/csharp/KernelEngine.<X>/` with `Native/` subfolder for auto-generated bindings. Build + tests + example 05 pass.
- **Steps**:
    1. For each `KernelEngine.<X>.Native` project: merge its content into `KernelEngine.<X>/Native/`.
    2. Update `.rsp` `--output` path.
    3. Update `csproj` removing the Native project reference (now the bindings are in the same project).
    4. Update `.slnx` to remove old Native projects.
    5. Adjust namespaces if needed (likely change `KernelEngine.<X>.Native` → `KernelEngine.<X>.Native` stays, just lives in same project).
    6. Update `scripts/generate_bindings.py` if it depends on old paths.
    7. Build + test.
- **Effort**: M (1 day). Mechanical but touches every plugin.

#### [W.16] Move `ke_console_sink_create` Out of the Kernel — ✅ Done (commit `ecbad90`, Option B)
- **Tags**: `refactor`, `bug` (Bug 1.38)
- **Why**: `ke_console_sink_create` is implemented in `src/c/kernel/src/logger/console_sink.c` and declared in the kernel's public API. **It is an implementation detail** (printf to stderr) — not a kernel building block. By the principle "kernel = building blocks, not built blocks", a concrete sink implementation does not belong in the kernel.
- **What**: Decide between:
    - **Option A**: Move to a new C++ plugin `KernelEngine.Logging.Console` (parallel to `KernelEngine.Logging.Serilog`). Exposes `ke_logger_sink ke_console_sink_create(...)` via standard plugin pattern.
    - **Option B**: Implement in C# directly inside `KernelEngine.Kernel.ConsoleSink` (already exists as a managed sink wrapper). Drop the C implementation entirely.
- **Recommendation**: Option B. The C# `ConsoleSink` exists already (`src/csharp/KernelEngine.Kernel/ConsoleSink.cs`). Verify it covers the C variant's use cases; if yes, delete the C version. Saves a header, a .c file, a binding, and a layer.
- **Acceptance**: `src/c/kernel/include/kernel_engine/kernel/logger/console_sink.h` deleted. `src/c/kernel/src/logger/console_sink.c` deleted. C consumers of `ke_console_sink_create` either rewritten or accept that console sinks are a C# concern.
- **Steps**:
    1. Audit C/C++ callers of `ke_console_sink_create` (likely just C examples).
    2. If callers exist in C examples and we want to keep C-only logging support, go with Option A. Otherwise Option B.
    3. Execute the chosen option. Delete the kernel files.
    4. Build + test.

#### [W.14] Misc Naming/Structure Cleanups — ✅ Done
- **Tags**: `chore`
- **What** (each is a small independent fix):
    1. ✅ Rename `KeTask.cs` → `KernelTask.cs` + class + `DispatchKeTask` → `DispatchKernelTask` (commit `2b6f9f4`).
    2. ✅ Rename `enki_task_scheduler_public.h` → `enki_task_scheduler.h` (commit `2b6f9f4`).
    3. ✅ Consolidated plugin threading headers into single `threading.h` (commit `a462d75`).
    4. ✅ Standardized `_export.h` location: all live under `include/kernel_engine/<domain>/` (Padrão B) (commit `36551ce`).

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

*Note: Examples 06–13 (E2E verification) and Track X (depth prepass, KTX2, etc.) are tracked in [`EngineRoadmap.md`](EngineRoadmap.md) under M1 since they are product-level milestones, not bug/refactor work.*

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

### Tier 3 — Fast Prototyping Base (M2 — Godot-like Framework)

> **All Tier 3 cards are blocked by Tier 1 stabilization (5 blocks).** They aim at Roadmap Milestone M2: framework usable like Godot.

#### [M2.1] Signals (Node-to-Node Events)
- **Tags**: `feat`
- **Why**: Godot's signals are the standard for decoupled node communication. Without them, nodes either hard-couple or use a global event bus (anti-pattern).
- **What**: Define a generic signal mechanism on `Node`: `node.Connect("damaged", target, "OnDamaged")` or C# events with managed dispatch. Decide between strongly-typed (C# events) vs string-keyed (Godot-style) — both have trade-offs.
- **Acceptance**: Two nodes communicate via signal in an example; no direct reference required.
- **Effort**: M (1–2 days). External lib option: not applicable; native C# events / pub-sub is sufficient.
- **Roadmap milestone**: M2.

#### [M2.2] Groups (Named Node Collections)
- **Tags**: `feat`
- **Why**: Godot pattern. `node.AddToGroup("enemies")` + `world.GetNodesInGroup("enemies")`. Used everywhere in Godot games.
- **What**: ECS tag component (zero-size) + query API.
- **Acceptance**: `Scene.AddNodeToGroup(node, "enemies")` works; query returns all members.
- **Effort**: S (half day).
- **Roadmap milestone**: M2.

#### [M2.3] Autoload Singletons
- **Tags**: `feat`
- **Why**: Godot pattern. `GameManager` always available without lookup. Common need for global services in gameplay code.
- **What**: Framework-level registry of "singleton nodes" instantiated at startup, accessible via `Autoload.Get<T>()`.
- **Acceptance**: An "Autoload" registered in DI is injected/accessible from any scene without explicit lookup.
- **Effort**: S.
- **Roadmap milestone**: M2.

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

### Tier 4 — Roadmap Features (M3–M5) and Optimization

> **All Tier 4 cards are blocked by Tiers 1, 2, and 3.** Roadmap milestones M3 (gameplay categories — physics/audio/UI/animation), M4 (visual editor), M5 (networking & advanced). Each card here targets one external library wrapped in a kernel vtable, per architectural principle #6.

#### 🎮 M3 — Gameplay Categories

##### [M3.1] Physics 3D — `ke_physics` vtable + Jolt backend
- **Tags**: `feat`
- **Why**: M3 milestone gate. Most game genres need rigid body physics, collision, raycast.
- **What**: Define `ke_physics` vtable (rigid body, collider shapes, world step, raycast). Backend plugin `KernelEngine.Physics.Jolt` wrapping JoltPhysics (modern, MIT, used by Horizon Zero Dawn).
- **Acceptance**: Example with falling cubes onto a plane, raycast hit detection.
- **Effort**: L (1–2 weeks).
- **Roadmap milestone**: M3.

##### [M3.2] Physics 2D — `ke_physics_2d` + Box2D backend
- **Tags**: `feat`
- **What**: 2D-specialized vtable. Box2D wrapper (mature, MIT).
- **Effort**: M (3–5 days).
- **Roadmap milestone**: M3. *Optional if 3D suffices for initial scope.*

##### [M3.3] Audio — `ke_audio` vtable + miniaudio backend
- **Tags**: `feat`
- **What**: vtable for play/stop/volume/3D positional. Backend: miniaudio (single-header, public domain).
- **Acceptance**: Example with positional audio (sound source moves with node).
- **Effort**: M (3–5 days).
- **Roadmap milestone**: M3.

##### [M3.4] Animation — `ke_animation` vtable + ozz-animation backend
- **Tags**: `feat`
- **What**: Skeletal animation, blend trees, AnimationPlayer node. Backend: ozz-animation (MIT, industrial).
- **Acceptance**: Example with rigged character playing walk + run blended.
- **Effort**: L (1–2 weeks).
- **Roadmap milestone**: M3.

##### [M3.5] UI — `ke_ui` vtable + Dear ImGui (dev) + RmlUi (game) backends
- **Tags**: `feat`
- **What**: ImGui for dev/debug overlays; RmlUi (HTML/CSS-like, MIT) for retained game UI.
- **Effort**: L (1–2 weeks for both backends).
- **Roadmap milestone**: M3.

##### [M3.6] Input action mapping
- **Tags**: `feat`
- **What**: Abstraction over raw key codes — actions like "jump", "fire" mapped to keyboard/gamepad/touch.
- **Effort**: M.
- **Roadmap milestone**: M3.

##### [M3.7] Save/load system
- **Tags**: `feat`
- **What**: Serialize world state, components, with versioning.
- **Effort**: M.
- **Roadmap milestone**: M3.

##### [M3.8] Particle system
- **Tags**: `feat`
- **What**: GPU compute via bgfx. Likely custom (no clear external lib for embedded engine).
- **Effort**: L. Research first.
- **Roadmap milestone**: M3.

##### [M3.9] Tween / AnimationPlayer (framework-only)
- **Tags**: `feat`
- **What**: Procedural animation of properties over time. Pure C# implementation.
- **Effort**: S–M.
- **Roadmap milestone**: M3.

#### 🎨 M4 — Visual Editor (entirely future)

##### [M4.1] Editor app shell
- **Tags**: `feat`
- **What**: Separate solution `KernelEngine.Editor/` consuming engine as library. Tech decision pending: Avalonia / WinUI / browser-based.
- **Effort**: XL.
- **Roadmap milestone**: M4. **Decide tech before estimating sub-cards.**

##### [M4.2] Scene inspector + property editor
- **Roadmap milestone**: M4.

##### [M4.3] Asset browser
- **Roadmap milestone**: M4.

##### [M4.4] Live preview (run game inside editor)
- **Roadmap milestone**: M4.

#### 🌐 M5 — Networking & Advanced

##### [M5.1] Networking transport — `ke_network` + GameNetworkingSockets (Valve, BSD) or ENet
- **Roadmap milestone**: M5.

##### [M5.2] Replication framework
- **Roadmap milestone**: M5. Built on top of `ke_network`.

##### [M5.3] GPU-driven rendering (indirect draw, GPU culling)
- **Roadmap milestone**: M5. Extends `ke_render`.

##### [M5.4] Real-time GI (DDGI / lumen-likes)
- **Roadmap milestone**: M5. Long-term R&D.

##### [M5.5] Ray tracing
- **Roadmap milestone**: M5. **Architectural decision needed**: bgfx doesn't expose RT — would need DX12/Vulkan direct backends.

#### ⚙️ Tier 4 — Optimization (existing)

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
- [ ] **Shadow projection bring-up** (example 06): shadow pipeline executes end-to-end (`Application` creates 1024² shadow map, `ShadowSystem` populates `packet.shadow.*`, `BeginShadowPass` runs, `u_lightVP`/`u_shadowParams` are now uploaded), but no shadow appears projected on the floor. Suspected: matrix convention mismatch between `ke_mat4_mul(p, v)` (row-major CPU) and `mul(u_lightVP, worldPos)` in `vs_basic.sc` (column-major GLSL), causing `v_shadowCoord` out of [0,1] so `ComputeShadow` always returns 1.0. Needs RenderDoc capture to confirm. Files: `src/cpp/render/core/src/shadow_pipeline.cpp`, `src/cpp/render/bgfx/shaders/vs_basic.sc`, `fs_basic.sc::ComputeShadow`.
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
| **1.27** | Plugin header exports non-`_create` C function (`get_last_fatal_error`) | **[W.7] get_last_fatal_error → ke_render vtable** | 📋 Todo |
| **1.28** | Plugin exports system factories as non-`_create` C functions (`bgfx_system_factory.h`) | **[W.9] Decide bgfx_system_factory fate** | 📋 Todo |
| **1.29** | Framework C# directly couples to `Bgfx.Native` bindings | **[W.7] + [W.9]** (resolves naturally) | 📋 Todo |
| **1.30** | Universal classes wrong namespace (`render::bgfx` for core/) | **[W.8] namespace rename** | 📋 Todo |
| **1.31** | Internal-only `.hpp` in `include/` (8 files in render/core) + class in shader_compiler public header | **[W.6] + [W.10]** | 📋 Todo |
| **1.32** | File extensions `.hh`/`.cc` violate convention (3 files) | **[W.10] + [W.11]** | 📋 Todo |
| **1.33** | PascalCase filenames violate snake_case rule (16 files) | **[W.12] snake_case rename** | 📋 Todo |
| **1.34** | `using namespace` (forbidden) — 4 violations | **[W.13] remove using namespace** | 📋 Todo |
| **1.35** | Naming/structure inconsistencies (KeTask, _public suffix, threading split, _export.h locations, KE_API misuse) | **[W.14] misc cleanups** | 📋 Todo |
| **1.36** | `KE_ID_*` macros declared but never used (cargo cult) | **[W.14] misc cleanups** (sub-item) | 📋 Todo |
| **1.37** | Vtables expose internal pointers (allocator, logger) as public fields | **(no card yet)** — needs separate audit | 📋 Todo |
| **1.38** | `ke_console_sink_create` doesn't belong in kernel | **[W.16] Move console_sink out of kernel** | 📋 Todo |
| **1.39** | Two-project plugin architecture is overengineering | **[W.15] Eliminate Native/ folder** | 📋 Todo |
| **1.40** | Hardcoded backend names in Framework error messages | **[W.14] misc cleanups** (sub-item) | 📋 Todo |
| **1.41** | Render pipeline uses magic numbers extensively (state bits, view IDs, format codes) — bug-prone, unreadable. Concrete instance: `WRITE_R\|WRITE_A` typo caused "tudo vermelho ou preto" bug in tonemap on 2026-05-16 | **[B4.2] Named constants** | 📋 Todo |
| **1.42** | `dotnet run --no-build` silently uses stale native DLL after `cmake --build` — multiple debug cycles wasted on "code rebuilt but no change" | **[B1.5] eliminate the stale-DLL trap** | 📋 Todo |
