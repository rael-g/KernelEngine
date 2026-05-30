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

## 🎯 Next Up — Beta Roadmap (Pong-retro reordered)

> **How to use this section**: pick the topmost open item from the current tier, work it to done, mark it ✅, move on. Items within a tier can be reordered; **do not skip ahead between tiers**.
>
> **Re-ordered after Pong retro (commit `8357944`)**: Pong shipped the first complete game and surfaced real ergonomic gaps. The new tier order is *(A) architectural debt → (B) non-physics/UI features → (C) physics+UI redesigns*. Items 1-5 of the original list (Project / scene / audio / physics MVP / Pong) are all ✅ done; what follows is what comes after.

### Tier A — Architectural debt (pay first, regardless of feature direction)

These cost us every time we touch them. None is physics- or UI-related; all surfaced during slices 1-5 of beta.

| # | Item | Why now | Detail |
|---|---|---|---|
| A1 | **Asset pipeline real implementation** | Today `SceneLoader` reads `.material` on each scene load; no cache, no manifest, no shipping path. Chapter 21 spec is pinned; implementing it removes a class of "works in dev, breaks shipped" bugs and unlocks asset hot-reload. | [Chapter 21](Reference/21%20-%20Asset%20Pipeline.md) |
| A2 | **Snapshot edge-poll deprecation** | `IsKeyPressed` is unreliable across the single-slot snapshot exchange (OBS.5 §3). Today we lean on events for edges, but the polling API is still public and lying. Either fix (accumulate in `InputBuffer`) or mark `[Obsolete]` and point at events. | OBS.5 §3 |
| A3 | **`Tree.AddNode(node, "Name")` ergonomics** | Pong's setup repeats `, "PaddleLeft"` etc. — name passed at every call site. Option: derive default from type name; override via `node.Name = ...` post-construction or a `[NodeName("Foo")]` attribute. | new |
| A4 | **Magic-default audit** | The Box2D plugin had a `if (gx == 0 && gy == 0) gy = -9.81f` "helpful default" that broke Pong's no-gravity setup. Sweep the codebase for similar patterns — defensive defaults that overwrite explicit user input. | retrospective |

### Tier B — Non-physics, non-UI features (build the missing pieces)

Concrete capability gaps surfaced by Pong or earlier examples that are not physics/UI.

| # | Item | Why | Detail |
|---|---|---|---|
| B1 | **Sprite + `Sprite2D` node** | Pong drew floor as a thin cube. Real 2D games need textured quads with pivot / UV / nine-slice. Renderer can absorb this without major refactor. | new |
| B2 | **`Camera2D` orthographic helper** | Pong placed a 3D camera at +Z faking ortho. Need a proper 2D camera node with pixel/unit scale + zoom. | new |
| B3 | **Headless mode + screenshot dump** | Unlocks CI visual regression + agent visibility (chapter 14 layer 3/4). | [Chapter 14 §4](Reference/14%20-%20Editor%2C%20CLI%20%26%20Agent%20Layer.md#4-the-five-layers-of-agent-visibility) |
| B4 | **CLI scaffold — `ke new project` / `ke run`** | Without it, creating a new project = copy-paste from `examples/`. Edges of the editor lib (chapter 18) get exercised. | [Chapter 18](Reference/18%20-%20Editor%20Lib%20API.md), [Chapter 19](Reference/19%20-%20CLI%20%26%20Agent%20Surface.md) |
| B5 | **Input action layer** | `Action.Jump` instead of `Key.Space`. Hard pre-req for gamepad / touch / VR; also the proper fix for OBS.5 §3 edge-poll. | [Chapter 22](Reference/22%20-%20Input%20Action%20Layer.md), expands `F.C2` |
| B6 | **Audio logical layer** | Bus mixer + clip pools + `.event` TOML. Beta-shippable game needs Music/SFX volume sliders at minimum. | [Chapter 23](Reference/23%20-%20Audio%20Logical%20Layer.md) |
| B7 | **OBS.6 — Point/spot shadows** | Visual completeness; expected for "modern engine". | [OBS.6](#obs6-point--spot-lights-cast-no-shadows-feature-deferred--future) |
| B8 | **Tracy profiler integration** | Helps every subsequent investigation. Tool, not a capability gap. | [B4.1](#b41-phase-n--tracy-profiler-integration) |

### Tier C — Physics + UI redesigns (do last)

Touchy and have ripple effects. Pin specs first (already done); implementation after Tiers A + B.

| # | Item | Why | Detail |
|---|---|---|---|
| C1 | **Physics node layer (`CollisionBody2D` + subtypes, auto-step, collision events)** | Pong's `PhysicsStepper` + manual body sync + hand-rolled hit detection are ergonomic debt. Spec pinned in chapter 24. Migrating Pong to it cuts the example by ~half. | [Chapter 24](Reference/24%20-%20Physics%20Node%20Layer.md) |
| C2 | **UI primitives — text rendering + minimal layout** | Pong's score is in console. No shipping game ships without on-screen text. Likely ImGui first (dev tooling), then a gameplay UI library (RmlUi or similar). | no chapter yet |

### Tier P — "Pong journey" continuation (post-cleanup-slice, before parking-lot)

After the F1/F2/cleanup slices, Pong is **scene-driven** end-to-end (4 sub-scenes + Project-driven config + auto-load action map + DI-injected nodes). The remaining items below take Pong from "works" to "shippable example", and unlock the workflow we actually want for users.

| # | Item | Why | Status |
|---|---|---|---|
| P1 | **UI primitives — text, layout, ImGui-first dev tooling** | Pong's score lives in `Console.WriteLine`. No real game ships without on-screen text. Replaces and supersedes [C2]. | new |
| P2 | **CLI editor — `ke add reference X`, `ke register defaultscene Y`, `ke register inputaction Z`** | Every change we made to `Project`, `*.scene`, `actions.input` was hand-edited TOML. The CLI must own those mutations (same API the future GUI editor will use) so users never touch them directly. Builds on [Chapter 18](Reference/18%20-%20Editor%20Lib%20API.md) / [Chapter 19](Reference/19%20-%20CLI%20%26%20Agent%20Surface.md). | new |
| P3 | **Auto-generated `Program.cs`** | Today, adding a plugin requires the user to edit `Program.cs` *and* `csproj`. The CLI should drive both: `ke add reference KernelEngine.Physics.Box2D` adds the `<ProjectReference>` *and* the `.AddBox2D()` line in `Program.cs`. User only writes gameplay scripts (Paddle.cs, Ball.cs); the bootstrap is generated from `Project` + reference manifest. | new |
| P4 | **Runtime fixture removal** | `IPhysics2D` lacks `RemoveFixture`; `CollisionShape2D` is add-only. Blocks "destroy a child collider at runtime" use cases (destructible armor, swap collision profile). Add the kernel method + wire `CollisionShape2D.OnDestroy`. | [Chapter 24 §8](Reference/24%20-%20Physics%20Node%20Layer.md#8-what-this-chapter-is-not) |
| P5 | **Audio loader alignment with Resource pattern** | Surfaced 2026-05-XX while building the text plugin. Textures + Models + Fonts all follow the same shape: `I{X}Loader.LoadXAsync` (CPU work, any thread) → `Assets.LoadXAsync` (async + cache + ref-count via `Resource`). Audio short-circuits this: `IAudio.LoadSound(path)` is **sync**, returns an opaque `SoundHandle`, no decode/upload split, no `Assets.LoadSoundAsync`, and `Sound` (framework wrapper) doesn't extend `Resource` (no ref-counting). It works for miniaudio (which has its own audio thread), but the shape is inconsistent with how every other asset is loaded; it leaks "asset-vs-runtime-stream" decisions into game code, and makes `Assets` an incomplete one-stop loader. Refactor: introduce `IAudioLoader.LoadSoundAsync(path) → AudioData`, then `Assets.LoadSoundAsync` orchestrates upload via `IAudioService` (or a new `SoundManager` mirroring `ResourceManager`) and returns a ref-counted `Sound : Resource`. **Caveat to think about during the refactor:** streaming audio (music tracks) doesn't fit the "decode entire file to RAM then upload" pattern — the new API has to leave a streaming hatch (or document that streaming is a separate API). | new |

Order: **P1 ✅ → P2 → P3**, then P4 / P5 / P6+ as needed. P3 depends on P2. Others independent.

### Tier P (continued) — surfaced 2026-05-29 during Pong code-review pass

After P1 shipped end-to-end, a pass over Pong's game-author surface (Paddle / Ball / Scoreboard / Main.scene) flagged framework-level ergonomic gaps that don't have a workaround in user code:

| # | Item | Why | Status |
|---|---|---|---|
| P7 | **`[NodeRef("path")]` attribute resolved by SceneLoader** | Today `GetNode<T>("../Sibling")` is a string-typed runtime lookup with no compile-time check; renaming a node in the scene silently breaks consumers. Replace with `[NodeRef("../Sibling")] Sibling? Other { get; private set; }` — SceneLoader assigns after Start, missing path = clear scene-load error. Same shape as Godot's `@onready` + `%UniqueName` and Unity's `[SerializeField]`. Pre-req for an editor-driven workflow (designer wires references visually). | new |
| P8 | **`async Task Start()` lifecycle support** | `protected override async void Start()` swallows exceptions into the scheduler — a font load that fails leaves labels invisible with no signal. `Tree.TickAwakeAndStart` should `await` an async overload + propagate exceptions through the existing `simException` path. Cosmetic for Pong (we patched with try/catch); structural fix benefits every async-loading node. | new |
| P9 | **`TriggerArea2D` + collision events** | Pong's goal detection is `if (pos.X > Field.HalfW + 0.5f)` — magic numbers + duplicated geometry knowledge with the scene's wall positions. Real fix: `TriggerArea2D` nodes "GoalLeft" / "GoalRight" in the scene firing `OnTriggerEnter(other)`. Depends on the kernel collision-event hook (chapter 24 step 5). **Same dependency** unblocks paddle-hit detection — Ball today uses a velocity-sign-flip heuristic (comment: "no collision events in F2 MVP"). | [Chapter 24 §6 step 5](Reference/24%20-%20Physics%20Node%20Layer.md) |
| P10 | **Designer-editable game tuning** | `Field.HalfW = 8f` is a hard-coded `const`. A designer wanting to tune the play area must edit C# + rebuild. Convention: a `[GameConfig]`-attributed POCO bound from a Project section (same pattern as `Box2DOptions` / `ConsoleSinkOptions`), OR a dedicated node like `GameSettings : Node` whose properties the scene file populates. Removes `Field.cs` as a tuning interface. | new |
| P11 | **Derive collider dimensions from the actual collision shape** | `Paddle.cs` has `const float HalfH = 0.9f` for the velocity-clamp boundary, but the real value lives in `Paddle.scene`'s `CollisionShape2D.Shape = { half_extents = [0.15, 0.9] }`. Two places, must stay in sync by hand. Helper API: `CollisionBody2D.GetShapeBounds() → Rect2` (walks `CollisionShape2D` children, reads the active `Shape2D` subtype). | new |
| P12 | **Pong production-grade pass — pause, restart, match end** | Pong currently plays forever. Real game: pause on Escape (or a pause key), win at first-to-N, return to title scene. Needs the scene-transition story figured out at framework level (load `Main.scene` fresh → resets all node state, which today there's no `Tree.Reload(scene)` for). Biggest lift of the bunch; exercises real "shippable game" gaps. | new |
| P13 | **CLI `using` cleanup must not rely on `KernelEngine.*` prefix** | Surfaced 2026-05-29 after P2 Slice 1. `ProgramCsSync.SyncUsings` only treats a `using` directive as ke-managed when its namespace starts with `KernelEngine.` — works today because every shipped plugin lives under that prefix, but breaks for any third-party plugin (e.g. `AcmeStudios.Network`): a `ke remove module` would leave its `using` orphaned in Program.cs because the cleanup rule wouldn't recognize it. The catalog already knows every module's `using` field; switch `SyncUsings` to remove only usings that appear in the *catalog* but not in the current manifest, regardless of prefix. No user-facing API change. | new |
| P14 | **`ke new <template>` should wrap `dotnet new <template>`** | Surfaced 2026-05-29 by the user immediately after P2 Slice 1: "evitar nós construirmos as coisas do zero quando ja existe alguma ferramenta capaz". Project scaffolding should ship as a `dotnet new` template pack (`ke.templates.game` or similar); `ke new game MyGame` shells out to `dotnet new ke-game --name MyGame` then does the minimum post-step (Project file with default sections, scenes/ folder skeleton, .gitattributes pull-in). Don't reinvent dotnet new's tokens / naming / sub-path logic. Same pattern for any future scaffold subverb. **MVP path (user OK'd 2026-05-29):** for the first cut just chain stock `dotnet new sln` + `dotnet new console` + a minimal Program.cs patch, no custom template pack yet — that path proves the wrapper shape; the curated template pack is the v1 polish so devs (and third-party authors) get richer starting points. **MVP shipped 2026-05-29** (commit pending) — `ke new game <Name>` produces sln+csproj+Program.cs+Project; v1 (template pack) deferred. |  MVP done |
| P15 | **`ke new game` scaffold cannot include `Application` bootstrap** | Surfaced 2026-05-29 during P14 MVP smoke. The previous scaffold used `using KernelEngine.Framework; using var app = new Application(); app.Run(services);` — but no ke-module exists that pulls `KernelEngine.Framework.csproj` on its own (Framework gets dragged in transitively by `InputActions` / `AudioFramework` / `Configuration`), so `ke add module KernelEngine.Kernel` alone leaves `Application` unresolvable. Current scaffold strips the bootstrap and only leaves a comment pointing the user at the missing pieces — works, but the goal ("user never touches Program.cs") is partially broken. Real fix: add a `KernelEngine.Framework` ke-module that's a bare csproj-ref + `using` declaration (no chain-method needed → also requires allowing empty `extension` in ModuleSpec), then have `ke new game` auto-add it so `Application` is in scope from day 1. | new |

P7/P8 are quality-of-life and cheap. P9 rides on collision events (already in spec). P10/P11 are convention/helper additions. P12 needs `Tree.Reload(scene)` which is a whole framework concept. P13 is a 20-line CLI fix once we touch SyncUsings again. P14 shapes how `ke new`/scaffolding subverbs are built whenever they land.

### Tier S — Scripting ABI / language-agnostic node system (post-beta replatforming)

> **Owner vision, captured 2026-05-28.** Original microkernel goal: `C kernel = building blocks`, `any language = Built Blocks (framework)`, `C# = personal sugar helper` — no language privileged. Reality during prototyping: `KernelEngine.Framework` (C#) absorbed `Node`/`Tree`/lifecycle/`SceneLoader`/action layer / Camera2D/Sprite2D/CollisionBody2D/AudioPlayer; C# became implicitly special. **Acceptable for now** because prototyping speed mattered more than ABI purity, but the drift gets paid down once the engine is shippable-game-ready.
>
> **Trigger**: only start after Tier P (UI + CLI + auto-Program) AND the deferred render-pipeline items (clustered forward shading [F.RC3], render-graph [F.RC2], etc. — see Parking lot) are done. Engine must be a viable game-building tool first.
>
> **Goal**: turn the C kernel into the actual scripting ABI. Each language (C#, Lua, Python, …) becomes a binding of equal status; the C# binding becomes one option of many, not the canonical surface.

**Architectural shifts required:**

| # | Item | Effort estimate |
|---|---|---|
| S1 | Expand `ke_script_component` with every lifecycle hook (`on_awake`/`on_start`/`on_update`/`on_late_update`/`on_destroy`/`on_input`/`on_input_action`) — today only `on_start`/`on_update`. | 1 week |
| S2 | Add `ke_node_type` registry + `set_property(entity, key, variant)` + `ke_variant` type to the C kernel — lets any language register a node type by string name and have the kernel populate properties without knowing the language's field model. | 2-3 weeks |
| S3 | Move SceneLoader from C# into the C kernel — TOML parser in C, scene instantiation via the node-type registry, callbacks to the active language binding. Today's C# SceneLoader becomes a thin wrapper. | 2-3 weeks |
| S4 | Move input action layer from C# into the C kernel — `.input` parser + dispatcher in C, callbacks for `on_input_action`. | 2 weeks |
| S5 | Refactor `KernelEngine.Framework` (C#) into a binding on top of the new ABI without ergonomic regression — Camera2D/Sprite2D/etc. stay as ergonomic C# wrappers, but they're now wrappers over ABI-defined primitives, not the source of truth. | 3-4 weeks |
| S6 | Validate by adding a second binding — **Lua (via LuaJIT or NLua)** is the recommended choice: small runtime (~500KB), trivial FFI, no GIL, suits embedding. Port Pong fully to Lua. | 4-6 weeks |
| S7 | ABI documentation + stabilization (once published, refactoring freedom shrinks; commit only after the spike validates the shape). | 1-2 weeks |

**Total: ~4-6 months focused.** Major architectural replatforming.

**Spike first (2-3 weeks) before committing the full project:** expand only `ke_script_component` (S1 lite) + write a minimal Lua binding that overrides `on_start`/`on_update` on a single class. Don't move SceneLoader or action layer yet. Just prove cross-language dispatch works with acceptable latency. Then decide.

**Open design questions to resolve during the spike:**
- Resources (`Mesh`/`Material`/`Sound`) cross-language: ref-counted C# class today; Lua userdata with `__gc`; Python ctypes-managed. ABI needs neutral handle + lifecycle.
- DI cross-language: `ActivatorUtilities` is .NET-specific. Each binding needs its own DI resolution from ctor signature in its language.
- Generics + enums: `IInputActionReader<TEnum>` is .NET-only. ABI must be non-generic (lookup by string-name); each binding adds typed overlay on top.
- Hot-reload: now becomes interesting per-binding; kernel needs "destroy all scripts of this type, reinstantiate with new factory".

### Parking lot — explicitly post-beta

- Visual editor GUI (M4) — chapter 18 prepares the lib; the GUI itself waits.
- **Render-graph + GPU-compute primitives ([F.RC2])** — universal extensibility surface for graphics techniques. SSAO/FXAA/TAA/SSR/DoF become registered passes; built-in bloom/SSAO/tonemap re-expressed through it (kills hardcoded view chain).
- **Clustered forward shading ([F.RC3])** — current brute-force caps at ~64 point / 48 spot; surplus silently dropped. Naturally rides on F.RC2.
- **GPU instancing + `MultiMeshRenderer` ([F.RC1])** — required for grass/crowds/particles at scale.
- Skeletal animation, networking, particles, save/load framework, joints/raycasts on top of physics layer (chapter 24 §8).
- MCP server for agents (CLI piping is enough for now — chapter 19 §9.2).

---

## 📋 Todo

### Tier 1 — Stabilization First (Current Focus)

> **Stabilization plan, locked 2026-05-08.** Coverage at 30.8% lines / 25.2% branches; render pipeline & threading at 0%; 94-commit branch never merged. Before alternating refactor/feature/bug/test work, we run **5 sequential blocks** to make the engine safe to evolve. Cards inside the same block can be parallelized; blocks must complete in order.
>
> Status will be tracked per block. Completing all 5 blocks is the gate to start M2/M3 features.

#### 🔧 BLOCK 1 — Close the long-lived branch (1–2 days)

##### [W.9] Eliminate `bgfx_system_factory.h` (unblock the branch)
*(Already detailed below. Pre-requisite for the rest of cleanup.)*

##### [B1.1] Final validation pass + merge `feat/multithread-architecture` to main — ✅ DONE (2026-05-21, merge commit `de97b24`)
- **Resolution**: W.9 verified done; build clean; ctest 179/179; dotnet test 80/80; example 05 confirmed. Merged with `--no-ff` (159 commits — main had not diverged). Branch kept locally as a safety net (not yet deleted).
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

##### [B1.5] Eliminate the `dotnet --no-build` stale-DLL trap — ✅ DONE by convention (2026-05-22)
- **Resolution**: no code. The trap only bites when `--no-build` skips the build (and thus the `PreserveNewest` native-DLL copy in `NativeDependencies.targets`); a build-time guard can't help since `--no-build` skips it too. Fixed as a workflow rule in `CLAUDE.md`: never use `dotnet run --no-build` — a normal `dotnet run`/`dotnet build` refreshes the native DLL by timestamp. Optional future hardening (a `scripts/check_native_freshness.py` mtime guard for CI/agents) deferred — not worth it for the human workflow.

<details><summary>original card</summary>
- **Tags**: `chore`, `bug` (Bug 1.42)
- **Why**: Running `dotnet run --no-build` after a native C++ rebuild silently uses the previously-deployed `.dll` in `bin/Debug/net10.0/` — the rebuild does NOT propagate. Symptoms: edited C++ code but example shows old behavior. Multiple agents (and the senior reviewer) have wasted debug cycles on this exactly.
- **What**: Either (a) drop `--no-build` from the standard run workflow (force `dotnet build` to copy fresh native DLLs), or (b) add a pre-run helper script that compares `build/native/bin/ke_*.dll` mtimes against the deployed copies in `examples/csharp/*/bin/Debug/net10.0/` and warns/copies on mismatch.
- **Acceptance**: Running the example after a `cmake --build` always picks up the latest native code without manual `dotnet build`. CI catches stale-deploy as an error.
- **Effort**: S (1–2 hours).
</details>

---

#### 🧪 BLOCK 2 — Test coverage where it hurts (3–5 days)

> Goal: lift coverage from 30.8% to **≥ 60%** in critical paths. Currently render/threading/Application = 0%. Any change to these is currently unsafe.

##### [B2.1] Unit tests for threading primitives (`KeThread`, `KeFrameSync`, `KeSemaphore`) — ✅ DONE (already covered; verified 2026-05-22)
- **Tags**: `test`
- **Status**: the "0% coverage" premise was **stale**. `tests/cpp/test_threading.cpp` already covers the card's scope: Thread create/join + `join_timeout` (timeout & success) + TLS-name (guards Bug 1.24); Semaphore signal/wait + counting; FrameSync handoff (producer/consumer) + blocking. All run green in ctest (part of the 179 C++ tests).
- **Remaining (minor, optional)**: a dedicated stress/race harness (many producers/consumers) if we ever want >80% confidence under contention; not needed for the gate.
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

##### [B4.2] Named constants for bgfx state bits + view IDs (replace magic numbers) — ✅ DONE (2026-05-22)
- **Resolution**: done the *correct* way (not the literal card). The magic numbers weren't just unreadable — the agnostic `render/core` passed raw bgfx state/clear bits to `IGpuDevice`, a layer leak (fails the swap test). Fix: semantic backend-agnostic enums `GpuClearFlags`/`GpuStateFlags` in the contract ([gpu_types.hpp](../src/cpp/render/contract/include/gpu_types.hpp)); `SetState`/`SetViewClear` take them; the **bgfx backend** translates to `BGFX_STATE_*`/`BGFX_CLEAR_*` (only place those live). View IDs centralised in `ViewId` enum ([view_ids.hpp](../src/cpp/render/core/src/view_ids.hpp)) in render/core (the device still sees `uint16_t` — agnostic). All call sites converted; acceptance grep empty; 179/179 C++ tests pass; visually confirmed no regression.
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
- **Phase 1 status**: ✅ Done (commit `e1dde51`).
- **Phase 2 progress** (10 commits, 2026-05-18 session — Hexagonal/Ports-and-Adapters approach):
  - ✅ Step 1: `KernelEngine.Kernel.Abstractions` assembly created with **22 types** (interfaces + managed records: LogLevel, Vertex, Lights, Handles, Transform, KernelResult, Result/KernelException, ComponentAccess, IAllocator/IArenaAllocator/IProxyAllocator/IMallocAllocator, ILogger, ILoggerSink, IDevPlatform, ITaskScheduler, IFrameSync, IFramePacket, IRenderer, IWindow, IInputReader, ISceneWriter, IResourceFactory, ISystem, IEcsRegistry, IWorld).
  - ✅ Step 2: `internal Native` → `public Native` on all wrappers; `InternalsVisibleTo` for plugin assemblies revoked (only Tests retained). Commit `fd0c65c`.
  - ✅ Step 5/Caso 1: `IDevPlatform.SetOsThreadName` managed method. Commit `d7d2256`.
  - ✅ Step 7/Caso 8: `AssetLoader` injects `TaskScheduler` via ctor; `LoadModelAsync` no longer takes scheduler param. Commit `877f1ba`.
  - ✅ Side: Node + Scene moved from Kernel to Framework. Commit `6c228de`.
  - ✅ Step 3: Framework.csproj decouple from Kernel — **DONE** (commit `1f8ee00`).
    Framework.csproj now references **only** `KernelEngine.Kernel.Abstractions`. Final pieces
    added: `IInputBuffer`, `IResourceCommandQueue` in Abstractions; `IEngineHost` extended with
    `CreateInputBuffer` / `CreateResourceCommandQueue` / `CreateSceneWriter` factories;
    `IInput.CaptureSnapshot() -> IInputReader`. `InputBuffer`, `ResourceCommandQueue`,
    `FramePacketSceneWriter` concretes implement their interfaces. `Application.cs` /
    `Node.cs` / `Scene.cs` use only Abstractions types. Builtin nodes use `AddComponent<T>`
    returning `Span<T>` instead of `ref T` / `T*`. Build green; 80 tests pass. Earlier in
    session (commit `b823d01`) `IEcsRegistry` got safe `Span<T>` accessors; commit `1ed7c70`
    added `IEngineHost`/`IKernelThread`/`IInput` + interface implementations on allocator /
    frame-sync / logger.
    Asset.Assimp dependency removed: `AssimpModelExtensions` was example-sugar disguised as
    engine utility (lossy flat scene, hid GPU uploads, forced a bridge assembly). Deleted from
    Framework; logic inlined into examples 12 & 13 with educational comments. Brief
    `KernelEngine.Framework.Assimp` bridge attempt also deleted (not committed). The residual
    `ke_vertex` leak (Asset.Assimp surfacing native `ke_vertex` via `ModelData.MeshData.Vertices`)
    is the catalyst for B5.6 below.
  - ✅ Step 6/Caso 3: `IFramePacket` rich managed API (SetCamera, SetDirectionalLight, AddPointLight, AddSpotLight, AddDrawCommand, AddShadowDrawCommand, SetSkybox, SetShadow, ...). 5 systems rewritten to use it; `unsafe` in Framework now contained to: `Mat4` helper, 4 minimal ECS-read blocks in systems, `Node`/`Scene` (ECS pointer storage), and `Application.InitializeSystems`. Examples folder: **zero `unsafe`**. Commit `3b57f11`.
  - ⏳ Step 8/Caso 2: `Component<T>` wrapper — **DEFERRED** to workflow layer (scriptable nodes).

- **Original plan reference** (for context):
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

##### [B5.8] Math = user's library; engine builds matrices in backend-declared NDC convention (ADR-10, revised) — ✅ DONE (2026-05-22)
- **Outcome**: dead C ops deleted (`math.h` keeps types + `from_transform`/`mul`); `ke_render.get_ndc_convention()` capability added + bgfx impl (reads `caps.homogeneousDepth`); `Mat4.cs` deleted → `Framework/Internal/ViewProjection.cs` (the explicit convention adapter: projection in backend NDC + RH `LookAt`) + System.Numerics for invert/vector math; `Application` captures the convention at init. Shadow validated visually after fixing the lookat handedness (System.Numerics `CreateLookAt` flips forward). 179 C++ + 80 C# tests green.
- **Tags**: `refactor`, `feat` (architecture)
- **Why**: Freedom philosophy — anyone can use any math lib, and a fork can ship any render backend. The real problem isn't "convert the user's matrix": the user passes **convention-neutral data** (pos/rot/scale, fov/near/far), so math-lib freedom already works with zero infra. The real problem is the engine's matrix **builders** (`Mat4.Perspective/Ortho`) **hardcode Vulkan [0,1]** → a forked OpenGL/D3D backend (z[-1,1], Y-flip) gets wrong projection/view. Full reasoning + the rejected matrix-adapter shape in **ADR-10** ([12 - Architecture Backlog & Decisions](Reference/12%20-%20Architecture%20Backlog%20%26%20Decisions.md)).
- **What**:
    1. **Delete dead C ops** (0 callers, verified): `ke_mat4_identity/_inv/_proj/_lookat/_ortho` in `math.h`. Keep the live internal helpers `ke_mat4_from_transform` + `ke_mat4_mul` (C TransformSystem in `world.c` — C, not C++, so GLM doesn't apply; document `mul == b·a`). Keep all `ke_*` ABI types.
    2. **Backend declares its NDC convention as a capability**: add `get_ndc_convention()` to the `ke_render` vtable → `{ z_range, y_flip, handedness }`. bgfx implements it (reads `caps.homogeneousDepth`).
    3. **Framework matrix builders consume it**: `Mat4.Perspective/Ortho/LookAt` build directly in the active backend's convention instead of hardcoding Vulkan. `Mat4.cs` stays (already de-pointered) — it becomes the single place that honors the capability.
    4. **No** `ke_math_convention` matrix-convert adapter / `convert()` — wrong shape (no foreign matrix crosses the boundary). Optional future: a per-input convention tag *if* we ever expose raw user-supplied view/proj matrices.
- **Acceptance**: dead `ke_mat4_*` ops gone; `ke_render.get_ndc_convention()` exists + bgfx implements; `Mat4.cs` builds from the capability (no hardcoded Vulkan constants); a (hypothetical) backend declaring `z_range=minus-one-to-one` would get a correct projection without touching game code or `Mat4.cs`; all examples render identically with bgfx.
- **Note**: not required for B5.1 (unsafe) — already done. The math-lib freedom (System.Numerics/GLM) needs **no** code — it already holds via the neutral-data boundary.
- **Effort**: M (delete dead ops = trivial; add capability to vtable + bgfx + wire 3 builders; visually validate).

##### [B5.6] Asset pipeline assembly — `IAssetLoader` + `IModel` abstractions
- **Tags**: `refactor`, `feat` (architecture)
- **Why**: `KernelEngine.Asset.Assimp` is a half-finished plugin: no kernel C vtable, no Abstractions interface, no dispatcher. Game code reaches a concrete `AssetLoader.LoadModelAsync` directly. Any "load a model" convenience method has nowhere to live (already tried a bridge assembly — rejected). Future loaders (KTX2, baked formats) will repeat the anti-pattern unless the contract is established first.
- **Progress (2026-05-20)**: the loader contract now exists. `IAssetLoader` + `IModel` / `IModelMesh` / `IModelMaterial` / `IModelTexture` live in `KernelEngine.Kernel.Abstractions`. Asset.Assimp's `AssetLoader` / `ModelData` / `MeshData` / `MaterialData` / `TextureData` were made **`internal`** and implement those interfaces; `AddAssimpAssetLoader()` registers `IAssetLoader` (not the concrete). `ke_vertex` leak gone — `IModelMesh.Vertices` returns `ReadOnlySpan<Vertex>` after an internal cast. Examples 12/13 resolve `IAssetLoader` via DI and touch zero plugin concretes / zero `KernelEngine.Kernel.Native`. Build green; 80 tests pass.
  - **Still pending below**: the `KernelEngine.AssetPipeline` coordinator assembly (dispatcher by extension + cache + baking), additional format loaders (KTX2, baked), `IModelNode` hierarchy preservation, and the `IModel.AddToSceneAsync(IScene, IResourceFactory, AssetHierarchyStrategy)` convenience in Framework.
- **What**: Introduce abstractions + a pipeline coordinator assembly. Per-format loaders become plugins that implement the contract. Framework consumes `IModel` only.
- **Pre-design** (subject to refinement when implemented):
    - **In `KernelEngine.Kernel.Abstractions`** (zero `unsafe`, zero native leak):
        - `IAssetLoader` — `KernelTask<IModel> LoadModelAsync(string path)`.
        - `IModel : IDisposable` — collections of `IModelMesh`, `IModelMaterial`, `IModelTexture`, plus optional `IModelNode Root` (Assimp/glTF hierarchy tree, preserved).
        - `IModelMesh` — `ReadOnlySpan<Vertex> Vertices`, `ReadOnlySpan<ushort> Indices`, `int MaterialIndex`, `string Name`.
        - `IModelMaterial` — PBR factors + texture indices + name.
        - `IModelTexture` — `Width`, `Height`, `ReadOnlySpan<byte> Pixels`, `Path`.
        - `IModelNode` — `string Name`, `Matrix4x4 LocalTransform`, `int[] MeshIndices`, `IReadOnlyList<IModelNode> Children`.
    - **New assembly `KernelEngine.AssetPipeline`** (depends on Abstractions only):
        - `IAssetPipeline` — dispatcher: `RegisterLoader(string extension, IAssetLoader)` + `LoadModelAsync(path)` routes to the right loader by extension.
        - `AssetCache` — `path → WeakReference<IModel>` with manual eviction (hot reload hook later).
        - Future (deferred): `BakingProcess` (raw → optimized binary), `IAssetWatcher` (filesystem watch + reload).
    - **Existing format plugins implement the contract**:
        - `KernelEngine.Asset.Assimp` — `AssimpAssetLoader : IAssetLoader` for fbx/gltf/obj. `ModelData` becomes internal; public surface is `IModel`. `ke_vertex` no longer leaks (`IModelMesh.Vertices` returns `ReadOnlySpan<Vertex>` after internal cast).
        - Future: `KernelEngine.Asset.Ktx2` for compressed textures, `KernelEngine.Asset.Bake` for engine-baked format.
    - **In `KernelEngine.Framework`** (still Abstractions-only):
        - Extension methods on `IModel`: e.g. `AddToSceneAsync(IModel, IScene, IResourceFactory, AssetHierarchyStrategy)`. Strategies: `Flat` (current example behavior), `PreserveHierarchy` (respects model node tree).
        - Convenience moves from examples back into the engine *only after* the abstraction is honest (no leaks, no half-baked types).
- **Acceptance**:
    - `grep -rn "ke_vertex" examples/csharp/` → no matches.
    - `grep -rn "KernelEngine.Kernel.Native" src/csharp/KernelEngine.Framework/ src/csharp/KernelEngine.AssetPipeline/` → no matches.
    - Adding a new loader requires only implementing `IAssetLoader`; no Framework or kernel change.
    - Examples 12/13 collapse back to `await pipeline.LoadModelAsync(path).AddToSceneAsync(scene, resources)`.
- **Effort**: M (1–2 days). Touches Asset.Assimp internals; risk is low because contract is small.
- **Depends on**: B5.1 phase 2 complete (✅).
- **What**: Add `internal Task<uint> EnqueueAsync(ResourceCommandType type, object data)` on `ResourceCommandFactory`. Update extensions to use it. Make `Queue` private.
- **Acceptance**: `grep "rcf.Queue" -r src/csharp/` → no matches. Extensions still functional.
- **Effort**: XS.

##### [B5.7] Make `Kernel.Abstractions` a cohesive managed mirror of the C kernel — relocate framework-policy contracts to Framework; delete `IEngineHost` — ✅ DONE
- **Status**: ✅ Done (commit `348c5c0`, 2026-05-20). `IEngineHost`/`EngineHost` deleted; replaced by focused `IKernelFactory` (one factory, zero policy in `AddKernel`). `ISceneWriter`/`IResourceFactory`/`IResourceCommandQueue`/`IInputBuffer` + concretes moved to `KernelEngine.Framework`; `InputSnapshotReader` stayed in Kernel. Thread affinity routed through `IKernelFactory.AssertCurrentThread` (no managed-TLS hack). `InternalsVisibleTo KernelEngine.Framework` removed (vestigial). `ConcurrencyTests` relocated to `Framework.Tests`. Build 0/0; 80 tests green. Deferred: optional `IShaderCompiler` to complete the mirror (~0.95:1).
- **Tags**: `refactor` (architecture)
- **Why**: `KernelEngine.Kernel.Abstractions` should be a cohesive **~0.9:1 managed mirror of the C kernel API** (span-reshaped for C# safety; see `docs/Reference/05 - C# Layers.md`). Two things break that cohesion: (a) `ISceneWriter` / `IResourceFactory` / `IResourceCommandQueue` / `IInputBuffer` encode the **Framework's 3-thread policy** — a framework decision leaking into the abstraction layer; an alternate framework (1 or N threads) should reuse Abstractions without inheriting our policy. (b) `IEngineHost` is a **service-locator / god-factory anti-pattern**; the project's pattern is DI.
- **What**:
    1. **Move policy contracts to Framework**: interfaces `ISceneWriter`, `IResourceFactory`, `IResourceCommandQueue`, `IInputBuffer` (from Abstractions) **and** concretes `FramePacketSceneWriter`, `ResourceCommandFactory`, `ResourceCommandQueue`, `InputBuffer` (from `KernelEngine.Kernel`) → into `KernelEngine.Framework`. Safe because these concretes depend only on **mirror interfaces** (`IFramePacket`/`IRenderer`/`IInputReader`), so no `Kernel→Framework` dependency and no cycle. No new `Framework.Abstractions` assembly — they live directly in Framework.
    2. **Delete `IEngineHost` + `EngineHost`**, replace with DI:
        - No-runtime-param factories (`CreateWorld`, `CreateFrameSync`) → register `IWorld`/`IFrameSync` in `AddKernel()` via factory lambdas; Framework resolves them.
        - Runtime-param factories (`CreateThread(name, fn)`, `CreateProxyAllocator(wrapped)`) → small typed factories registered in DI (`IThreadFactory.Create(name, fn)`, etc.) — DI + factory, not service location.
        - Policy factories (`CreateInputBuffer`/`CreateResourceCommandQueue`/`CreateSceneWriter`) → gone; Framework `new`s the concretes (now local).
    3. Rewire `Application.cs` to take resolved services / typed factories via DI instead of `IEngineHost`.
    4. Move `InputBuffer` / `ResourceCommandQueue` tests from `KernelEngine.Kernel.Tests` (`ConcurrencyTests`) → `KernelEngine.Framework.Tests`.
    5. (Optional) add `IShaderCompiler` to Abstractions to complete the mirror (~0.95:1).
- **Acceptance**:
    - `Kernel.Abstractions` contains only kernel-mirror contracts + POCOs; grep there finds no `ISceneWriter`/`IResourceFactory`/`IResourceCommandQueue`/`IInputBuffer`/`IEngineHost`.
    - `grep -rn "IEngineHost" src/csharp/` → no matches.
    - `Framework` references only `Abstractions`; `Kernel`/plugins do **not** reference `Framework`; no dependency cycle.
    - Build green; all tests pass (relocated tests included).
- **Effort**: M.
- **Depends on**: B5.1 phase 2 (✅).

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

## 🎮 Tier 2 — Framework High-Level API (hide building blocks from game code)

> **Initiative locked 2026-05-20.** Architectural premise: `KernelEngine.Kernel.Abstractions` is the **building-blocks API** (renderer, GPU resources, ECS, raw input, frame packet) — for engine/plugin authors. **Game developers must never import it.** `KernelEngine.Framework` is the high-level façade they use. Framework already covers `Application`, `Scene`/`Node`, camera/light/mesh nodes, and the render systems — but game code still leaks into 5 blocks (measured in examples 06/12/13). This initiative closes those leaks.
>
> **Leaks today**: `IResourceFactory` + raw handles + `Vertex[]` (in `OnReady`); `ISceneWriter` post-fx/ambient/clear (per-frame in `OnUpdate`); `IInputReader.IsKeyDown(87)` magic keycodes; `IWorld.ActiveCamera = node.Entity` (raw entity IDs); manual GPU-upload loop after `IAssetLoader`. Math types (`Vector*`, `Quaternion`, `Matrix4x4`, `Transform`) are universal and stay.
>
> **Order**: A → B → C → D (largest leak first; Tier A alone removes ~80% of `OnReady`, Tier B clears `OnUpdate`). Then G/H (Godot-inspired scene graph + events). E/F per roadmap. Each card's acceptance gate: the target leak no longer appears in `examples/csharp/`.

##### [F.0] Foundational decision — Node is an OOP view over the ECS (RATIFIED 2026-05-20)
- **Decision**: Game devs author with typed Nodes only; the sparse-set ECS is an **invisible execution backend**. (User confirmed this was always the intent.)
- **Consequences**:
    - `*Component` structs (Transform/Mesh/Light/…) and `uint componentId` **leave the public Framework API** — they become internal, touched only by render/transform systems.
    - Node properties read/write ECS data internally (`meshRenderer.Mesh = …` writes `MeshComponent` behind the scenes).
- **Why this is not slower than an OOP engine (e.g. Godot)**: Godot itself uses thin nodes over data-oriented "servers"; we use thin nodes over ECS. The hot paths (render, transform) iterate packed ECS arrays for cache efficiency. **Accepted trade**: per-node script callbacks (`OnUpdate`) keep virtual-dispatch cost (same as Godot); ECS-pure engines (Bevy/DOTS) avoid it but lose OOP ergonomics. Deliberate choice: ergonomics for gameplay code, ECS for system iteration. Good for typical games (hundreds–low thousands of active entities); not aimed at 10k+ scripted-node simulations.
- **Naming policy**: use **.NET / Unity-like** terms, NOT Godot's — *but only when sufficiently descriptive*. `Tag` (not Group), node events via C# `event`/delegates (not "signals"), `FixedUpdate` (not `_physics_process`), `SceneManager` (not SceneTree). **Reuse unit is NOT called "Prefab"** — see F.0a.

##### [F.0a] Composition model — node tree, behaviors are nodes (RATIFIED 2026-05-20)
- **Decision**: gameplay is composed by **nesting child nodes** (Godot-style), not by an attached-behavior list. A `Player` node has child nodes for `MeshRenderer`, `RigidBody`, and even behavior like `Health`. The dev MAY consolidate everything into the `Player` subclass if they prefer — it's their choice, not forced.
- **Gameplay state lives as plain managed fields on nodes** — NOT ECS components. A `Health` node is one class with a `Current` field + `OnUpdate`; no `HealthComponent`, no `HealthSystem`. As cohesive as Godot. The only thing that reaches the ECS is the internal `ScriptComponent` (invisible).
- **Rejected**: the earlier "create a Component + System for every custom node" model — incohesive for gameplay (scatters one concept across three files). The user explicitly disliked it.
- **Rejected**: "Prefab" as the reuse-unit name — *everything is a Scene*, so a separate "Prefab" concept is a weak Unity-ism. A reusable subtree is just a `Scene` you `Instantiate()` (see F.G2).

##### [F.0b] Escape-hatch principle — logic/data vs capability (RATIFIED 2026-05-20)
- **When a user hits a wall, ask: is the missing thing LOGIC/DATA or a CAPABILITY?**
    - **Logic/data** (custom AI, mass simulation of entities with custom behavior) → solvable in **user-land**: nodes, node-behaviors, or (advanced opt-in) a custom ECS component+system in the Framework layer. The ability to run logic and iterate data already exists.
    - **Capability** (GPU instancing, a new shading model, a new collider type) → **NOT** solvable in user-land no matter how well data is organized, because the feature lives below the ECS layer (renderer/physics contract). The engine must extend the contract.
- **Worked example — rendering a million grass blades**: node-per-blade is catastrophic; a custom component+system does NOT fix it because `IFramePacket.AddDrawCommand` issues one draw per transform — the bottleneck is a missing **GPU-instancing capability**, not data layout. Correct answer is NOT engine-specific grass code, NOR the user hand-extending the bgfx plugin — it is the engine exposing GPU instancing as a **building-block primitive** (renderer contract) + a high-level `MultiMeshRenderer` node. Then grass/crowds/particles become *content the user authors*, and nobody writes grass-specific engine code. (Consistent with "kernel = building blocks, never built blocks".) → tracked as [F.RC1].

##### [F.RC1] GPU instancing primitive + `MultiMeshRenderer` node (render capability)
- **Tags**: `feat` (rendering), roadmap M2/M3
- **Why**: No way today to draw many instances of one mesh in few draw calls. Blocks grass, foliage, crowds, particles, debris, asteroid fields. Surfaced by the F.0b grass analysis.
- **What**: (1) **Primitive in the renderer contract** — instanced draw: one mesh + material + a per-instance buffer (transform + optional per-instance data), issued as one/few draw calls. Implemented in the bgfx plugin. (2) **High-level `MultiMeshRenderer` node** in Framework (à la Godot `MultiMeshInstance3D`) — game dev sets a mesh + a list/buffer of instance transforms; never touches the renderer.
- **Acceptance**: an example renders 100k+ instances of one mesh at interactive framerate via a single high-level node; zero plugin code written by the game dev.
- **Effort**: M–L (touches kernel frame-packet contract + bgfx + a Framework node).

##### [F.RC2] Render-graph + GPU-compute primitives as UNIVERSAL kernel contracts (extensibility doctrine)
- **Tags**: `feat` (architecture), roadmap (post-functional). Doctrine: [docs/Reference/13 - Extensibility & Universality.md].
- **Why**: The project's competitive bet is decentralized extensibility (Linux formula) — a dev adds any graphics technique (FXAA, SSAO, TAA, …, up to Nanite) as a **plugin** without forking the core, and it must survive a render-backend swap (bgfx→OpenGL). For that, the extension surface must be a **kernel contract**, not a render-plugin invention (else it binds users to bgfx).
- **What**:
    1. **`ke_render_graph` kernel contract** — register a pass `{ type (fullscreen|geometry|compute), reads:[named resources], writes:[named resource], shader, insertion point }`; engine resolves the graph + manages intermediate targets. Each backend plugin implements it. Built-in bloom/SSAO/tonemap re-expressed as registered passes (kills the current hardcoded view chain / OBS.4 fragility).
    2. **Standardized named resources** (`scene_color`, `depth`, `normal`, `velocity`…) every backend must expose, so technique plugins are backend-agnostic.
    3. **GPU-compute/buffer primitives in the render contract** — structured/storage buffers, compute dispatch (incl. indirect), writable storage images, atomics (incl. 64-bit), GPU-driven indirect draw, custom/opaque resource types. **Prerequisite for ALL GPU-driven techniques** (GPU particles, GPU culling, virtual texturing, Nanite). Surfaced by the Nanite validation exercise (Reference ch.13): orchestration infra is sufficient, but these primitives are the missing universal layer.
    4. **Capability negotiation** (`isSupported`) + portable shader authoring (cross-compiled by the shader-compiler plugin).
    5. **Custom materials/shaders** (Godot `ShaderMaterial` style) — per-object custom surface shaders; fullscreen-quad effect = a registered fullscreen pass.
- **Acceptance (validation)**: a third-party `AddMyFXAA()` plugin adds a post-pass with zero core changes; swapping the bgfx plugin for another backend keeps it working (only shaders change). Stretch: GPU particles implemented purely as a plugin via the compute primitives.
- **Effort**: L (foundational). Strictly **after** the engine is functional (user's call). Don't over-promote speculative parts; render-graph + named resources + compute primitives are clearly universal.

##### [F.RC2.Resume] Render-graph Phase 4.4 — continuation checkpoint (2026-05-29)
- **Branch**: `feat/render-graph`. Phases 1–3, 4.1, **4.2, 4.3** done.
- **Phase 4.3 shipped (2026-05-29)**: `fs_basic.sc` migrated from brute-force uniform loops to cluster-buffer lookup. Added `BUFFER_RO` bindings (stages 5–10) for b_pointLightsFS, b_spotLightsFS, b_pointLightIndices, b_pointLightCount, b_spotLightIndices, b_spotLightCount. `ComputeClusterIndex(fragCoord)` helper reconstructs view-space Z from Vulkan NDC depth [0,1] + exponential slice (Olsson 2012). `ClusteredForward::BindForSceneRead` sets 6 `SetBuffer` + 2 uniforms per draw call. `FrameSubmitter::Submit` accepts nullable `ClusteredForward*` and calls `BindForSceneRead` inside the scene draw loop. All 20/20 shaders compile. **Open question**: bgfx's `setBuffer` is documented as compute-only — runtime test with example 09 needed to confirm BUFFER_RO works in fragment shaders under bgfx Vulkan. If not, fallback = texture-buffer approach (store cluster data in RGBA32F texture and sample in fragment shader). Spot light outer_angle missing (3 vec4 packing; outer ≈ 90% of inner for now).
- **Next session entry point (Phase 4.4)**: run example 09 (~200 point lights) and verify (a) no crash, (b) all 200 lights contribute (no silent 64-cap dropout). If `setBuffer` is ignored for draw calls, implement texture-buffer fallback for cluster index data. Otherwise, cleanup: remove unused `u_pointLights[128]`/`u_spotLights[192]` uniform declarations from fs_basic.sc and stop calling `UploadLights` for the brute-force path.

##### [F.RC2.Cleanup] Render-graph Phase 6 — decompose `scene.legacy_remaining` monolithic pass
- **Tags**: `refactor` (render), follow-up to F.RC2 merge
- **Why**: After Phases 1-5 ship, 5 of the 6 active graph passes are real (`shadow.directional` / `skybox.composite` / `ssao.compose` / `postfx.composite` / `ui.overlay`). The sixth — `scene.legacy_remaining` — still wraps `FrameSubmitter::Submit` whole-cloth: global state, lighting upload, clustered light-cull compute dispatch, scene view transform, env-tex IBL resolution, AND the main scene draw loop. It runs as one graph node, so the doctrine win ("orchestration flows through the executor") is preserved, but the internal monolith blocks per-concern observability and prevents user passes from inserting *between* these stages.
- **Why it's still monolithic**: every sub-stage shares uniforms (lights, camera_pos, env_tex). Splitting them naively would force re-uploading the same uniform 3× per frame and risk a state-cache miss between submits. Decomposition needs storage buffers replacing the uniform path so each pass sets only what it changes — same mechanic that already powers `clustered_forward`.
- **What** — micro pre-plan (3 sub-splits, each its own commit, validate visually between each):
    1. **`lights.upload` (compute or fullscreen pass, no draws)** — CPU packs `point_lights`/`spot_lights` arrays, uploads to `b_pointLights` + `b_spotLights` storage buffers (already exists in `clustered_forward`). Pass writes a logical "lights_uploaded" sentinel resource so the DAG can order anything that reads light data after it. Removes `lighting.SetDirectionalLight` + uniform writes from `FrameSubmitter`.
    2. **`lights.cluster_cull` (compute pass)** — pure dispatch wrapper around `clustered_.DispatchLightCull`. Reads `lights_uploaded`; writes the cluster output buffers (declared as transient storage resources). Removes `clustered_.UpdateClusterBounds + DispatchLightCull` from `FrameSubmitter` — they become the pass body.
    3. **`scene.opaque` (geometry pass)** — only the draw loop. Reads `shadow_map`, cluster output, env_tex (still a uniform until IBL is buffer-ified). Writes `backbuffer` (rename target then to something honest like `scene_hdr`). When done, `FrameSubmitter::Submit` shrinks to a 5-line wrapper or is deleted entirely; the `SubmitPacketLegacy` indirection goes too.
- **Acceptance**: `SubmitPacketLegacy` deleted, `FrameSubmitter.cpp` deleted. All examples (01-15 + Pong) render identically before/after each sub-split. **— SHIPPED 2026-05-30 (commits 6b1ac09 → 5ec8f70) on the feat/render-graph branch ahead of merge.**
- **Effort**: M (3 commits × ~1h each, the validation hops being the slow part).
- **Risk**: getting uniforms-to-buffers wrong is the same class of bug we hit at clustered shading bring-up (compute-write buffer rule, descriptor binding ordering). In practice the only regression we hit was a one-line cull-dispatch removal that black-screened many-lights — caught visually, fixed in the next iteration.
- **Follow-up (separate card)**: `view_ids.hpp` enum still lives in `src/cpp/render/core/src/` and is used by 4 internal `.cpp` files to bind specific bgfx view ids (Shadow=0, Scene=1, …). Not a vestige — it's a well-encapsulated private detail. Retiring it requires the graph executor to *own* view-id assignment as source of truth and pass the assigned id to each pass via `ke_render_pass_ctx` (new accessor). Reasonable future work but disjoint from this cleanup; surfaced here as a known limit, not a blocker.

##### [F.RC3] Clustered forward shading — finish the job
- **Tags**: `feat` (rendering), post-beta, naturally rides on [F.RC2]
- **Why**: Today's brute-force point/spot loops in `fs_basic.sc` are capped at ~64 point / 48 spot lights. Scenes that exceed (example 09 places ~200) silently drop surplus lights. The original "clustered" implementation was wired through the kernel but never completed in the fragment shader; what shipped is brute-force, not clustered. Memory docs claiming "unlimited lights, dynamic grid" are stale and have been corrected.
- **What**:
    1. Cluster build (compute pass): assign lights to a 3D screen-space frustum grid. Existing kernel scaffolding (`ClusteredForward` class under `src/cpp/render/core/`) is the starting point — audit what's salvageable vs needs redo.
    2. Fragment shader: replace the brute-force loops in `fs_basic.sc` with a clustered loop reading the cluster buffer + light index list.
    3. Resolve the secondary bgfx warning `Failed to find memory that supports flags 0x00000003` at init (compute buffer creation flags — likely device-local+host-visible mismatch).
- **Acceptance**: example 09 (200 point lights) renders correctly with no silent light dropouts; profile shows clustering wins vs brute force at high counts.
- **Dependency**: cleaner if done *after* [F.RC2] (render-graph + compute primitives) — clustered build naturally expresses as a compute pass in the graph. Doing it before F.RC2 means more hardcoded view chain, which F.RC2 will then rewrite.
- **Effort**: M (after F.RC2 lands), L (if attempted standalone before F.RC2).

#### Reference harvest — Luna.Core (studied 2026-05-22, folder then deleted)

> A prior OOP framework (`Luna.Core`) was studied for reusable ideas/code. Its **core** (single-thread `Host.Run` loop, retained-mode render keyed by node UID, `Injector` service-locator DI) is **incompatible** with our 3-thread + frame-packet + ECS model and was NOT taken. What we kept:
>
> **Lifted as code (done):** input enums + `InputReaderExtensions` (F.C1), `Time` (F.E1), and an `Animation/` library (`Easing`, `AnimationBase`, `Tween`, `AnimationCurve`, `KeyframeAnimation`, `Timing`) in Framework — self-contained, not yet wired to nodes (driver comes with the animation domain, M2+).
>
> **Kept as design reference (implement our way, ECS-backed):**
> - **Everything is a Node** — Luna had `PerspectiveCamera`/`OrthographicCamera`, `DirectionalLight`/`PointLight`/`SpotLight`, `Model`, primitives (`Box`/`Rectangle`/`Ellipse`/`Label`), `Skybox`, `Sound`, `PostProcessor` all as nodes. Validates **F.0a** and the **F.D5** node taxonomy/rename target.
> - **Node lifecycle vocabulary** — `Awake`/`Start`/`EarlyUpdate`/`Update`/`LateUpdate`/`FixedUpdate` + `On*` action hooks + async `ExecuteAsync` + main-thread marshalling. Target set for **F.H2** (today we only have OnStart/OnUpdate via ScriptComponent).
> - **Input as events** — `Node.Input(InputEvent)` propagated down the tree (`KeyboardEvent`/`MouseButtonEvent`/`MousePositionEvent`/`MouseScrollEvent`). The fix for OBS.5#3 (edge events) → **F.H3**: an event queue, not snapshot polling.
> - **Transform ergonomics** — `GlobalPosition`/`GlobalRotation`/`GlobalScale` (computed up the parent chain), `Origin` (pivot), `EulerAngles`/`Quaternion` convenience, `ModelMatrix()` compose order. Target API surface for **F.D** (our world matrix stays computed in C).
> - **Scene query** — `FindNode("Head/Mouth/Tongue")` path lookup, a `Tree` UID index, `GetAllNodesOfType<T>()`. Target for **F.D4**.
> - **Camera resolution** — a node with no camera walks up parents to find one. Nice ergonomic for the camera/node work (F.D1).

#### Tier A — Resources & assets (largest leak)

> Reframe `Material` / `Mesh` / `Texture` / model as a **shared, ref-counted asset family** (Unity-like `Asset` / .NET resource semantics): loadable by path, cached, ownership-tracked. F.A4 (`Assets`/`AssetManager`) is the loader/cache façade for the family.

##### [F.A1] High-level `Material` type
- **Why**: Game code juggles raw `MaterialHandle` from `IResourceFactory.CreateMaterial`.
- **What**: Managed `Material` with presets — `Material.Pbr(baseColor, metallic, roughness)`, `Material.Unlit(color)`, `.WithAlbedo(Texture)`, `.WithNormalMap(Texture)`. Encapsulates the handle + lifecycle. `MeshNode { Material = mat }` instead of `MaterialHandle`.
- **Acceptance**: no `MaterialHandle` / `CreateMaterial` in `examples/csharp/`.

##### [F.A2] High-level `Mesh` + primitive factory
- **Why**: Example 06 hand-builds a cube in ~40 lines; game code touches `Vertex[]` + `CreateMesh` + `MeshHandle`.
- **What**: `Mesh.Cube()`, `Mesh.Sphere(segments)`, `Mesh.Plane()`, `Mesh.Quad()`, `Mesh.FromVertices(...)`. Hides `Vertex[]` and the handle.
- **Acceptance**: no `Vertex[]` / `MeshHandle` / `CreateMesh` in `examples/csharp/`.

##### [F.A3] High-level `Texture` type
- **Why**: `TextureLoader` exists but returns a raw `TextureHandle`.
- **What**: `Texture.Load(path)`, `Texture.Cubemap(paths)`, `Texture.White`. Hides `TextureHandle` / `CreateTexture` / `CreateCubemap`.
- **Acceptance**: no `TextureHandle` in game code.

##### [F.A4] `Assets` / `AssetManager` service
- **Why**: Single entry point for loading + caching.
- **What**: `assets.LoadModel(path)`, `assets.LoadTexture(path)` with cache + ref-count + (future) hot-reload. Hides `IAssetLoader` and `IResourceFactory` behind one façade.
- **Acceptance**: game code resolves `Assets`, never `IAssetLoader` / `IResourceFactory`.

##### [F.A5] `scene.Add(model)` / `model.Instantiate(scene)`
- **Why**: This is the home for the `AddToScene` helper deleted from examples (see [B5.6]).
- **What**: Operates on `IModel`; strategies `Flat` / `PreserveHierarchy`. Replaces the manual texture→material→mesh upload loop in examples 12/13.
- **Acceptance**: examples 12/13 collapse to `scene.Add(assets.LoadModel("box.gltf"))`.
- **Depends on**: B5.6 (`IModelNode` for `PreserveHierarchy`).

#### Tier B — Environment & render config (move out of `OnUpdate`)

##### [F.B1] `Scene.Environment`
- **What**: Persistent properties set once: `AmbientLight`, `ClearColor`, `Skybox`, (future) `Fog`. Render systems consume them.
- **Acceptance**: no `ClearColor` / `SetAmbientLight` calls in `OnUpdate`.

##### [F.B2] `Scene.PostProcessing`
- **What**: Config object with toggles/props: `.Bloom = new BloomSettings { Threshold, Intensity }`, `.Ssao = ...`, `.Tonemapping = ...`.
- **Acceptance**: `ISceneWriter` post-fx calls gone from game code; `ISceneWriter` becomes an internal detail consumed only by render systems.

#### Tier C — High-level input

##### [F.C1] `Key` / `MouseButton` enums — ✅ DONE (2026-05-22)
- **What**: `Input.IsKeyDown(Key.W)` instead of `87`.
- **Resolution**: lifted GLFW-aligned enums (`Key`, `MouseButton`, `InputAction`, `KeyModifiers`) into `Kernel.Abstractions/Input/` from the Luna.Core reference; added `InputReaderExtensions` typed overloads (`IsKeyDown(Key)`/`IsMouseButtonDown(MouseButton)`) — plain casts, zero implementer churn. Example 00 converted off raw keycodes. Closes OBS.5#2.
- **Remaining**: sweep other examples that still poll raw ints (none currently besides 00, done).

##### [F.C2] Input action/axis mapping
- **What**: `input.Bind("MoveForward", Key.W, Key.Up)`, then `input.GetAxis("Move")` / `input.IsActionPressed("Jump")`. Decouples gameplay from physical keys (enables gamepad later).

##### [F.C3] Framework `Input` façade
- **What**: Wraps `IInputReader`, exposed via the typed update callback. Game code never sees `IInputReader`.

#### Tier D — Scene / camera / entity ergonomics (hide IDs)

##### [F.D1] `scene.MainCamera = cameraNode`
- **What**: Kills `ActiveWorld.ActiveCamera = node.Entity`. No `Entity` (ulong) in game code.
- **Acceptance**: no `.Entity` access in `examples/csharp/`.

##### [F.D2] Reusable camera controllers
- **What**: `OrbitCameraController`, `FlyCameraController`, `FpsCameraController` — ready-made behaviors (otherwise hand-written with raw input).

##### [F.D3] Typed component access without component IDs
- **What**: Node subclasses use `AddComponent<T>(SomeNode.ComponentId)` today. Hide the `uint componentId` — `node.Add<PointLightComponent>(...)` resolving the ID internally.

##### [F.D4] Node query/find + tags + paths
- **What**: `scene.Find(name)`, `node.Find("Player/Sprite")` (relative path), `scene.OfType<MeshRenderer>()`. **Tags** (Unity-like, == Godot groups): `node.AddTag("enemy")`, `scene.FindWithTag("enemy")`.

##### [F.D5] Node-type rename to Unity/.NET convention
- **What**: Rename built-in nodes to clear single-responsibility names: `MeshNode` → `MeshRenderer`, `CameraNode` → `Camera`, `LightNode`/`PointLightNode`/`SpotLightNode` → `DirectionalLight`/`PointLight`/`SpotLight`. The node type IS the "component" (no Unity-style component list); composition is by nesting child nodes.
- **Acceptance**: examples use `new MeshRenderer { Mesh = …, Material = … }`, no `*Node`/`*Component` suffixes leaking intent.

#### Tier G — Scene composition & reuse (Godot-inspired, .NET naming)

##### [F.G1] Hierarchy ergonomics
- **What**: `parent.AddChild(child)` (replaces `scene.AddNode(child, parent:)`), `node.GetParent()`, `node.GetChild(i)`, child iteration. Add `node.GlobalTransform` (setter converts into parent space) alongside the existing local `WorldMatrix`.

##### [F.G2] Scene as the universal reuse unit (code-first; serialization later)
- **Model**: **everything is a `Scene`** — a node subtree with a single root. The running world AND any reusable piece are both Scenes. There is **no separate "Prefab" type** (rejected in F.0a). Reuse = `scene.Instantiate()` → a deep-copied detached root you plug in via `parent.AddChild(...)` / `scene.Add(...)`.
- **Phase 1 (now): code-based** — a Scene factory (class/method) builds and returns a root node + children; instantiate as many as you want.
- **Phase 2 (deferred): `SceneAsset`** — the serialized on-disk form, part of the Tier A asset family. `assets.LoadScene("enemy.kescene")` → returns a `Scene` you `.Instantiate()`. Name is descriptive in .NET terms ("the asset that becomes a Scene"); drops both `Prefab` and Godot's `PackedScene`. Ties into the offline asset pipeline on the roadmap.

##### [F.G3] `SceneManager` (scene switching)
- **What**: Global manager: active scene, `LoadScene` / `ChangeScene`, global pause, tag propagation. Ties into F.G2 (a scene loads as an instantiated `Scene` root) and F.A4 (asset loading).

#### Tier H — Events & lifecycle

##### [F.H1] Node events (Godot signals → C# events)
- **What**: Decoupled events on nodes via idiomatic C# `event`/delegates: declare, subscribe, raise. Fills the "Observer planned later" gap left when MessagePipe was removed (see [[project_messagepipe_removed]]).

##### [F.H2] Richer lifecycle callbacks
- **What**: Add `OnFixedUpdate(dt)` (fixed timestep, Unity-like — for physics/determinism), `OnEnable`/`OnDisable`/`OnDestroy`, `OnEnterTree`/`OnExitTree`. Today only `OnStart`/`OnUpdate` exist.

##### [F.H3] Event-based input
- **What**: Push input events (key down/up, mouse, scroll) to nodes via `OnInput(InputEvent)` in addition to the polled `Input` façade (F.C3). Lets gameplay react without polling every frame.

#### Tier E — Gameplay plumbing

##### [F.E1] `Time` service — 🚧 PARTIAL (2026-05-22)
- **What**: `Time.DeltaTime`, `Time.TotalTime`, `Time.FrameCount`. (Today only the `dt` parameter.)
- **Done**: static `Time` in Framework (`Time.DeltaTime`, `Time.ElapsedTime`) driven by `Time.NewFrame()` at the top of the ke.sim loop (Application.cs). Lifted/adapted from Luna.Core.
- **Remaining**: `FrameCount`; `FixedDeltaTime` once a fixed-step loop exists; expose to node callbacks.

##### [F.E2] Richer behaviors (evaluate — may be premature)
- **What**: Timers, `Invoke(delay)`, coroutines, scene events beyond `OnStart`/`OnUpdate`.

#### Tier F — Future domains (M2–M5) — principle, not a card yet

> When audio / physics / UI / animation / networking land: **each gets a Framework façade**, never raw plugin access. Same rule as the asset loader (Tier A) — plugin implements a contract in Abstractions, Framework exposes the high-level type, game dev never touches the concrete. This is a standing architectural principle for every new domain.

---

## 🔎 Example-Verification Observations (running tech-debt log)

> Captured while visually verifying examples 06–13 (2026-05-21 session). Defects, hardcoded values, magic numbers, and anti-patterns to refactor later. **Principle (user, 2026-05-21)**: hardcoded render/scene params belong in the *example* (game-dev choice), not buried in the engine/framework. Later they become Framework presets (ties into Tier 2 / F.B Scene.Environment + PostProcessing).

##### [OBS.1] Hardcoded render params buried in framework — surface to examples / presets
- **Tags**: `refactor`, tech-debt
- **Findings**:
    - Shadow **resolution `1024×1024`** hardcoded in `Application.cs` (`Renderer.CreateShadowMap(1024,1024)`). Game dev can't change it.
    - Shadow **frustum/near/far/distance** hardcoded in `ShadowRenderSystem.cs` (`Mat4.Ortho(-20,20,-20,20, 0.1, 50)`, `eye = lightDir*25`).
    - (accumulating — add ambient defaults, light angles, cluster counts, etc. as found.)
- **Should be**: example-level props/settings now (e.g. `ShadowSettings { Resolution, FrustumSize, Near, Far }`), Framework presets later (F.B).
- **Effort**: M.

##### [OBS.2] Examples 07/08/09 render dark — fragment shader never accumulates point/spot lights (BUG)
- **Tags**: `bug`
- **Symptom**: 07 (point), 08 (spot), 09 (many) render as **dark screens, zero illumination**. Directional lighting (06) works.
- **Root cause (confirmed 2026-05-21)**: `src/cpp/render/bgfx/shaders/fs_basic.sc` **declares** `u_pointLights[128]`, `u_spotLights[192]`, `u_clusterParams2` but its `main()` only accumulates the **directional** light + ambient/IBL. There is **no point/spot light loop at all** (neither brute-force nor clustered). Lights DO reach the frame packet and the uniforms (verified via temp log: `point=4 spot=0 has_dir=0 draw=36` for 07) — the shader simply ignores them. The "clustered forward shading" was never wired into the fragment shader (or the loop was lost).
- **NOT a regression** of the C# refactor — the C# `LightRenderSystem` records the lights correctly.
- **Secondary**: bgfx `Failed to find memory that supports flags 0x00000003` (device-local+host-visible) at init — likely the cluster-cull compute buffers; their result isn't consumed by `fs_basic` anyway. Investigate separately.
- **Fix**: implement point/spot accumulation in `fs_basic.sc`. Either (a) brute-force loop over the uniform arrays (works for ≤128 point / ≤? spot, simplest), or (b) full clustered loop reading the cull buffer (matches the "unlimited lights" intent; 09 has 200 → exceeds 128, so clustered is needed for it). Decide approach before implementing.
- **Status (updated 2026-05-22)**: ✅ **brute-force loops implemented** — `fs_basic.sc` now accumulates point ([fs_basic.sc:118-128](../src/cpp/render/bgfx/shaders/fs_basic.sc#L118-L128)) and spot ([:130-144](../src/cpp/render/bgfx/shaders/fs_basic.sc#L130-L144)) lights (Cook-Torrance `PbrDirect` + linear-squared attenuation; spot adds cone falloff). 07/08/09/13 now light up; confirmed visually. **Remaining gap**: brute-force is capped (`u_pointLights[128]` / `u_spotLights[192]` → ~64 point / 48 spot effective); the clustered path (option b) for >cap counts (09 places ~200) is still unimplemented — surplus lights are silently ignored. Clustered remains deferred.

##### [OBS.3] Examples 12/13 asset loading — "prototyped, never ran" bugs (FIXED inline) + brittle asset path
- **Tags**: `bug` (fixed), tech-debt
- **Fixed inline (2026-05-21)**: (1) `AssetLoader` needs `KernelEngine.Kernel.TaskScheduler` but 12/13 never registered it → added `.AddEnkiTaskScheduler()` + the `KernelEngine.TaskScheduler.Enki` ProjectReference. (2) model path used 5 `..` levels (resolved to `examples/assets/`, nonexistent) → corrected to 6 (`assets/` is at repo root). Model now loads (`1 mesh, 2 materials`).
- **Tech-debt (anti-pattern, defer)**: locating assets via `Path.Combine(AppContext.BaseDirectory, "../../../../../../assets/...")` is brittle (breaks if output depth changes). Should copy assets to output (csproj `<Content>`) or resolve via a robust asset-root lookup. Ties into the future asset pipeline (B5.6).

##### [OBS.4] Examples 10/11 post-processing pipelines broken (BUG, deferred — complex)
- **Tags**: `bug`
- **Symptoms (2026-05-21 visual)**: **10 hdr_bloom** → entirely black screen (HDR FB → tonemap composite path not reaching backbuffer, or nothing lit). **11 ssao** → dark-blue background with several black quads clustered in the lower-left corner (geometry projecting to wrong screen region — gbuffer-prepass/SSAO viewport or fullscreen-quad UV issue).
- **Status**: deferred — post-FX pipeline bugs (HDR composite, SSAO gbuffer prepass) are complex and "prototyped, never validated". Needs a focused iterative-visual session (like the shadow bring-up).
- **Diagnosis (2026-05-21)**: the SubmitPacket/SubmitPostProcess **orchestration looks structurally correct** — scene→HDR FB (view 1), bloom bright/blur (views 3/4/5), tonemap composite (view 6 → backbuffer/`kGpuInvalidHandle`), state `WRITE_RGBA`, fullscreen quad bound, view IDs ordered. So 10's black screen is NOT an obvious orchestration bug; it's deeper — likely in `fs_tonemap` (UV/sampling of the HDR texture), the fullscreen-quad NDC geometry, or the HDR texture format/sampling. 11's corner-quads point at the SSAO gbuffer-prepass fullscreen/viewport or `vs_prepass`/`vs_fullscreen` UVs. Both need shader-level visual iteration. All examples build + run (no crash) with the new lighting shader.
- **SSAO root cause (2026-05-21, confirmed)**: `PostProcessPipeline::SetupSsao` ([src/cpp/render/core/src/post_process_pipeline.cpp:114](../src/cpp/render/core/src/post_process_pipeline.cpp#L114)) is an **empty stub** (`// Implementation placeholder; return KE_OK`). Consequence chain: the gbuffer FB is never created → the SSAO/prepass pass in `SubmitPacket` is skipped (`GetGbufFb()` invalid) → `s_ssaoBlurred` stays the default white texture (AO=1) → **SSAO has zero visible effect**. The contact darkening seen in example 11 is **100% directional shadow-map shadows**, not SSAO. `scene.SetSsao(...)` is a no-op until this is implemented. Example 11 was cleaned up to document this (commit `216c510`).
- **Note**: 12 (asset+directional) renders correctly; 13's box+Sun render, only its floor had the quad-orientation bug (fixed) and its orbiting point lights are dark (OBS.2).

##### [OBS.5] Framework ergonomics gaps surfaced during example 11 (refactor, deferred)
- **Tags**: `refactor`, `framework`
- **Why**: While bringing up example 11 these authoring rough edges appeared. None are bugs (engine behaves as built) but each forces game code to drop to low-level/magic values — exactly what Tier 2 should hide.
- **Items**:
    1. **No `CameraNode.LookAt(target, up)` helper.** Game code must hand-build orientation: `Quaternion.CreateFromRotationMatrix(Matrix4x4.CreateWorld(eye, Vector3.Normalize(target-eye), Vector3.UnitY))`. The camera looks down local -Z (`CameraRenderSystem` uses `Mat4.InvertTrs(WorldMatrix)`, no look-at). Add a `LookAt` convenience on `CameraNode`.
    2. ✅ **RESOLVED (2026-05-22)** — `Key`/`MouseButton`/`InputAction`/`KeyModifiers` enums + `InputReaderExtensions` overloads added (F.C1); game code now reads `input.IsKeyDown(Key.Space)`.
    3. **Edge events unreliable over the lock-free input buffer.** `IsKeyPressed` (press-edge) is unreliable because `InputBuffer` is a single-slot *snapshot* exchange — fast press/release between sim frames is lost. Edge detection needs an **event queue** (key-down/up events drained per frame), not snapshot diffing. Only `IsKeyDown` (level) is reliable today.

##### [OBS.7] Directional shadow not visible in example 06_shadow_map (BUG, pre-existing on main)
- **Tags**: `bug`, `render`
- **Symptoms (2026-05-29 visual)**: `dotnet run --project examples/csharp/06_shadow_map` renders the scene + lighting normally but the **projected shadow of the cube on the ground plane is absent**. Reproduces on `main` independent of the `feat/render-graph` branch — surfaced during render-graph Phase 3 visual validation, NOT introduced by the graph rewrite.
- **Diagnosis so far**:
    - ShadowPipeline pipeline runs end-to-end: `BeginShadowPass` is called with valid `packet->shadow.map_handle` (idx=0), 2 shadow draws submitted via `SubmitMeshShadow` to view 0, light_view/light_proj matrices non-zero and plausibly correct for a 25-unit eye distance + (-20,20,-20,20,0.1,50) ortho.
    - Scene draw path sees `active_shadow_handle.idx=0` + `shadow_tex=8` (valid bgfx handle) at `SetTexture(2, shadows.shadow_map_uniform, shadow_tex, ...)` time, so the s_shadowMap sampler IS bound to the shadow target — not to the white fallback.
    - That isolates the failure to one of: (a) `fs_shadow` not actually writing `gl_FragCoord.z` to the R32F color attachment (shadow map stays at clear=1.0); (b) `u_lightVP` set in BeginShadowPass not surviving into `fs_basic`'s `v_shadowCoord = mul(u_lightVP, worldPos)` (uniform overwrite or per-draw scoping?); (c) `u_shadowParams.x` not actually > 0.5 when `fs_basic.sc:113` evaluates; (d) `coord.z - 0.005 > texture2D(s_shadowMap, coord.xy).x` always false because the depth values written/sampled are on incompatible scales (NDC vs [0,1]).
- **Next**: needs a focused shader-level visual session (RenderDoc capture of view 0's R32F attachment + the per-fragment shadow sampler value in view 1, against the legacy known-good build).
- **Not blocking render-graph work** — the regression is independent. F.RC2 Phase 3 can ship without OBS.7 fixed; the broken shadow will resurface only when this fix lands.

##### [OBS.6] Point & spot lights cast no shadows (feature, deferred — future)
- **Tags**: `feature`, `render`
- **Why**: Only the **directional** light has a shadow map today. In `fs_basic.sc` point/spot lights are accumulated "forward, **unshadowed**" ([fs_basic.sc:115](../src/cpp/render/bgfx/shaders/fs_basic.sc#L115)) — they correctly brighten even directional-shadowed regions (shadow only attenuates the directional term, [:113](../src/cpp/render/bgfx/shaders/fs_basic.sc#L113)), but they cast no shadows of their own. Surfaced in example 13: orbiting point lights light the box but objects don't occlude each other's point-light contribution.
- **What**: Add omni/spot shadows. **Spot** = a perspective depth map per light (same shape as the existing directional ortho map). **Point/omni** = a cube depth map (6 faces) or a dual-paraboloid map per light. Needs: per-light shadow-map allocation + atlas/array management, shadow VP upload per light, and a `ComputeShadow`-style lookup inside the point/spot loops.
- **Acceptance**: a scene with two boxes + one point light shows one box shadowing the other from that light.
- **Scope note**: substantial — per-light shadow passes multiply draw cost; almost certainly wants to ride on the future render-graph (F.RC2) rather than be hardcoded into the current view chain. Defer until render-graph lands or a focused shadow session.

###### Target architecture — a robust, performant shadow system
> Current system is **minimalist**: a single fixed-size directional ortho map (1024², hardcoded frustum — see OBS.1), one shadow pass on view 0, basic depth-compare in `ComputeShadow` with a constant bias (`coord.z - 0.005`). It works for one directional light and does not scale to many lights or large scenes. The robust target below is what to build when implementing OBS.6; design it as render-graph passes (F.RC2), not hardcoded views.

- **Directional → Cascaded Shadow Maps (CSM).** Split the view frustum into N depth slices (typ. 3–4), each with its own ortho light-map sized to its slice → near objects get high resolution, far ones low, no wasted texels. Per-cascade: stabilize the projection (snap the light ortho to texel-size increments) to kill shimmering as the camera moves; blend a band between cascades to hide seams. Upload N light-VPs + split distances; the fragment picks its cascade by view-space depth.
- **Spot → single perspective depth map.** Same shape as today's directional map but with the light's perspective projection. Cheapest non-directional shadow.
- **Point/omni → cube depth map or dual-paraboloid.** Cube = 6 perspective passes (one per face); dual-paraboloid = 2 passes, cheaper but with edge artifacts. Store linear distance (not post-projection depth) for a clean cube compare.
- **Shadow atlas + per-light budget.** Allocate all live shadow maps from **one large texture atlas** (e.g. 4096²) carved into tiles, instead of N separate render targets. A per-frame **tile allocator** sizes each light's tile by importance (distance to camera, screen coverage, intensity) and skips off-screen / fully-attenuated lights entirely. Bounds total shadow memory and binds; one sampler, many lookups by UV-rect.
- **Caching for static lights/geometry.** A light whose transform and casters didn't move keeps its rendered tile across frames (dirty-flag invalidation). Most lights in a scene are static → re-render only what moved. Biggest single perf win for many-light scenes.
- **Culling per shadow view.** Cull casters against each light's frustum/sphere before the depth pass (reuse the scene's spatial structure). Optionally tighten the directional ortho to the visible casters' bounds.
- **Filtering / quality.** PCF (NxN taps) as the baseline soft edge; PCSS or a variance/exponential map (VSM/ESM) for contact-hardening soft shadows. Bias as **slope-scaled depth bias + normal-offset** (not the current constant) to remove acne without large peter-panning.
- **Capability-gated.** Per the universality doctrine, expose a `shadowQuality`/cascade-count knob and degrade gracefully when a backend lacks compare-samplers or array textures (`isSupported`).

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

#### [SceneNode] Composable scenes (terminology realigned 2026-05-20)
- ⚠️ **Realigned to the F.0a / F.G2 model**: there is **no `Prefab` and no separate `SceneNode` type**. Everything is a `Scene` (a node subtree); reuse = `scene.Instantiate()` added as a child. This card now == [F.G2] phase 2 (file-backed `SceneAsset`).
- **Why**: Allow a scene to reference other scene assets as children, enabling complex hierarchies.
- **What**: A child node whose subtree is produced by `assets.LoadScene(path).Instantiate()`.
- **Acceptance**: A "Player" scene composed of "Body" and "Weapon" scenes via instantiation.
- **Steps**:
    1. Recursive instantiation of a loaded `Scene`.
    2. Per-instance property overrides.
- **Overlap note**: see [F.G2]/[F.G3]. This + W.2 (.kscene) + M2.1 (Signals) + M2.2 (Groups) duplicate new Tier 2 cards F.G2, F.H1, F.D4 — **needs a reconciliation pass** (decide which numbering wins) before either is scheduled.

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
