# Engine Architecture Kanban

Technical roadmap for KernelEngine hardening, ECS refinement, and framework foundation.

---

## 🚨 Next-session priority — completion audit sweep

The Kanban has drifted out of sync with reality: multiple cards listed as parking-lot, planned, or in-flight have *already shipped* without anyone updating their status. Confirmed instances so far:

- **[F.RC2] Render-graph + GPU-compute primitives** — listed in Parking Lot, but `src/c/kernel/include/kernel_engine/kernel/render/render_graph.h` (242 lines) + `src/cpp/render/core/src/render_graph_impl.hpp` (137 lines) are present and shipped. The card should move to Done.md and any dependent cards (`[UPSCALER-PREP]`, [F.RC2.Resume], [F.RC2.Cleanup]) need re-evaluation.
- **OBS.4 — Bloom black screen** — flagged as broken in the OBS log, but may have been silently fixed during the post-process refactor. Verify before propagating "bloom is broken" in any future doc / response.
- Likely more (B5.* cleanup cards, several F.A/F.B/F.C/F.D entries that were absorbed silently during the framework iterations).

**Before any new feature work**: spend one session walking every card under "🎯 Next Up" + Parking Lot + OBS log against the actual codebase and either tick it ✅ done (move to Done.md) or confirm it's genuinely open. Stale Kanban entries cost more than the audit itself — they cause us to plan against fiction.

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
| A5 | **Drop `impl_*` / `XxxImpl` / `*_impl.{hpp,cpp}` naming across C++ plugins** | Tautological noise that grew by inertia, not doctrine — every function in `.cpp` is impl, every state struct behind a vtable handle is "the impl". Affects 9 files: `scene_loader.cpp`, `asset_resolver.cpp`, `input_actions.cpp`, `resource_queue.cpp` (framework); `core_renderer.cpp`, `render_graph_impl.{cpp,hpp}`, `bgfx_shader_compiler.cpp` + `_impl.hpp` (render); `ke_frame_sync.cpp` (threading). Rename: `impl_<verb>` → `<plugin>_<verb>` (matches kernel C convention already in CLAUDE.md); `XxxImpl` → `XxxState`; files ending `_impl.{hpp,cpp}` → drop the suffix (`render_graph_impl.hpp` → `render_graph.hpp` or fold inline). Mechanical refactor, no behavior change. | new |
| A6 | **Source-comment sweep — banish "what" / "history" comments** | CLAUDE.md already says "Default to writing no comments. Only add one when the WHY is non-obvious", but it isn't enforced and the codebase is full of rot: `// Phase 5.6: ...`, `// Bug 1.42`, `// Legacy [[node]] type=…`, `// registry is ignored — kept in the signature for one release`, XML docs that read "Phase 2 of the ECS-pure-nodes refactor", `///` blocks narrating what was removed/renamed. These age into lies because the plans/bugs/PRs they reference disappear. **Patterns to banish**: any reference to Phase X / Bug Y / "was" / "now uses" / "removed" / "deleted in" / PR or commit names / refactor plan names. **Keep**: rare WHY comments that explain a non-obvious constraint, invariant, or workaround. **Method**: grep-driven sweep across `*.cs` `*.cpp` `*.h` `*.hpp`, remove offending comments per file, single commit per logical area. Optional follow-up: clang-tidy / Roslyn analyzer rule that fails CI on banned tokens (`Phase \d`, `Bug \d`, `(was|now) `). | new |
| A7 | **Doc deduplication + reference rot purge** | `docs/Reference/` documents features that don't exist (asset pipeline chapter 21, editor lib chapter 18, agent layer chapter 14, etc.) AND duplicates content that belongs in headers (API descriptions). Result: the code disagrees with the docs in many places, and the docs lie because they describe "what we wanted" not "what shipped". **Plan**: (a) any chapter that describes API → migrate to Doxygen/XML doc on the actual public symbol; delete the markdown. (b) any chapter that describes unshipped features → either move to the public Roadmap section (brief bullet) or delete (becomes new content in A9 when shipped). (c) keep markdown only for: roadmap, dated architectural decisions, philosophy, getting-started. Outcome: single source of truth per topic; if it isn't in the code, it doesn't exist. Pre-req for A8 (autogen needs to be where API docs live). | new |
| A8 | **DocFX pipeline — unified C# + C/C++ API reference site** | Static-site generator that ingests both .NET XML doc comments and Doxygen XML, emits one searchable site with C# and C/C++ APIs cross-referenced. **Stack**: Doxygen over `src/c/kernel/include/` (public headers only) → emits XML → DocFX consumes Doxygen XML + csproj XML docs → static site in `build/docs/`. **Deployment**: GitHub Pages on `gh-pages` branch via CI workflow `docs.yml` (runs on push to main). **Theme**: stock `modern` theme — don't invent. **Enforcement**: CI fails if any `public` symbol lacks a docstring. **Alternatives ruled out**: Sphinx+Breathe (poor C# story); raw Doxygen HTML (no unification); MkDocs/Hugo + custom adapters (maintenance burden). Pre-req: A6 + A7 (sweep + dedup must precede automated extraction or the autogen inherits the rot). | new |
| A9 | **Public docs site skeleton — open-source-grade structure (content fills over time)** | Even pre-1.0 with shifting APIs, we need the *shape* of a serious docs site in place now so future content has a home and visitors can navigate even when pages are stubs. **Site structure** (delivered as DocFX TOC + page scaffolds): `Home` (landing with one-liner, philosophy callout, status badge "Pre-1.0 / API in flux", CTAs) → `Quick Start` (install + 30-line hello window + link to Pong) → **`Philosophy`** (dedicated section, prominently placed: microkernel doctrine, universal-or-nothing, C ABI + sugar above, Philosophy>YAGNI, API-canonical not implementation-canonical [GAMEPLAY-CONTRACTS link], concurrency by construction [DEADLOCK-FREE link]) → `Manual` (concepts: layers, ECS, threading, resource pipeline, scenes & nodes, input actions, assets, plugin authoring) → `Tutorials` (Pong as canonical reference; "write a custom render backend"; "write a Lua/Rust binding") → `API Reference` (autogen from A8) → `Roadmap` (BRIEF — status table ✅/🚧/📋 per high-level feature so visitors know what's planned; explicitly NOT the Kanban) → `Migration Guides` (empty until first post-1.0 breaking change) → `Contributing` → `License + Acknowledgments` (engine license + every wrapped lib's license: bgfx, GLFW, Box2D, miniaudio, assimp, stb, enkiTS, tomlplusplus). **Out of public docs** (stays in `docs/` private): Kanban, Bug catalog, Architecture Backlog & Decisions, refactor plan docs. **Initial state at landing**: Quick Start + Philosophy + API Reference (rich from day 1 thanks to autogen) + Roadmap brief are filled; Manual and Tutorials ship as stubs labeled "(coming with M2)". **Hosting**: `docs.kernelengine.dev` (or GH Pages subpath) — decided when first publishing. Pre-req: A8 (pipeline exists). | new |

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
| B10 | **LOD pipeline — meshoptimizer plugin + `LodGroupComponent` + selector system** | Asking a modeller to ship `mesh_lod0/1/2/3.fbx` by hand is 2010 workflow. Pipeline: wrap **zeux/meshoptimizer** (MIT, mature, used by everyone) as `KernelEngine.Asset.MeshOptimizer` plugin → at asset bake time, generate a LOD cascade per mesh (e.g. 100% / 50% / 25% / 12%); store the cascade in the baked asset. Runtime: `LodGroupComponent { Mesh[] cascade, float[] screenSizeThresholds }` + `LodSelectionSystem` picks which LOD to draw based on camera distance or screen-space size. Standard pattern across UE5 / Unity / Godot. Pre-req for any "open world" / large scene example. Independent of the Nanite-class research; that's a separate parking-lot consideration. | new |
| B9 | **RenderDoc integration / capture hook** ⚠️ **do BEFORE any future render-related feature or refactor** | Today render bugs (OBS.4 bloom black screen, OBS.7 etc.) are debugged by guesswork + `printf`. RenderDoc captures a full frame's GPU state (every draw, every bound resource, every shader, every framebuffer) and lets us inspect it pixel-by-pixel — turns "why is the screen black" from a multi-hour bisect into minutes. Bgfx + Vulkan work with RenderDoc out-of-the-box; integration is mostly: document the workflow, add a debug-build hook for `RENDERDOC_API_1_x_x` programmatic captures (optional), keep PDB symbols intact. **Mandatory pre-req for**: any new render feature (deferred shading, depth prepass, point/spot shadows, clustered forward), any render refactor (view layout, post-process chain, backend swap), and any visual-regression debugging. Shipping render work without RenderDoc in the toolbox = paying the OBS.4-style debug tax every time. | new |

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
| P16 | **Window lifecycle bug cluster (4 bugs, likely shared root in threading shutdown/resize path)** | Surfaced 2026-05-30 from accumulated user notes. (a) **Close-hang**: clicking X paints the window white and waits ~5s before exit; log shows `[ERROR] Application: ke.sim did not stop within 5s ? forcing exit`. (b) **Resize-freeze**: dragging the window edge does NOT resize the rendered framebuffer with the window AND freezes the render thread. (c) **Startup-white**: window appears blank for several seconds before the first rendered frame shows. (d) **Title encoding**: dash/em-dash in window title renders as `<?>` (UTF-8 not honored on the Win32 SetWindowText path). User suspects (a) is recent ("é um pouco mais recente"); (b)(c)(d) have been there "desde sempre ou a muito tempo". Likely all related to the 3-thread architecture (ke.main/ke.sim/ke.render): sim doesn't see the close signal in time, resize event from main isn't propagated to render, render takes time to spin up before first packet arrives, title is encoded somewhere as ASCII. Investigate together — fixing one likely surfaces the others. **Backend-dependent (discovered 2026-05-31 after F.BA shipped):** under D3D11, (b) resize works correctly AND (c) startup-white is absent (small delay only). Under Vulkan both bugs are present and (a) close-hang delay is also longer. Strongly suggests root cause is in the bgfx Vulkan swapchain/`bgfx::reset` path, not in the GLFW plugin (same C# code, two different outcomes per backend). Implication for the fix: test on BOTH backends — a "fix" that only works on Vulkan probably hides a workaround that shouldn't exist; a fix that breaks D3D11 means agnostic code started compensating for Vulkan-only behavior (F.BA coupling regression D.2 would catch). | new |
| P17 | **Window icons** | While we're touching the window (P16), add the engine/app icon support. GLFW exposes `glfwSetWindowIcon(window, count, images)` taking an array of `GLFWimage` (raw RGBA pixels at multiple sizes — typical 16/32/48/256). Plugin surface: `ke_window.set_icon(rgba_pixels[], width, height)` on the kernel vtable, GLFW plugin implements; multi-size variant later. Project TOML: `[runtime.window] icon = "res://assets/icon.png"` loaded via stb_image at startup. Per-platform fallback: Windows reads embedded .ico from the executable as well (separate, lower priority). | new |
| P18 | **Docs polish — comments + Getting Started** | User flagged on 2026-05-30 that some inline comments and the docs Getting Started chapter are stale or missing post-F.RC2/F.BA-era. Pass: re-read `docs/Reference/00 - Overview.md` + ensure first-touch examples (01_window_scene through Pong) match current API; sweep source comments for outdated framing ("ke.sim does X" when X moved to ke.render, etc.). No deep redesign — just bring text in sync with code. | new |
| P19 | **CLI `ke build shaders` — integrated UI over the shader pipeline** (scope confirmed 2026-05-30) | The single user-facing command to compile shaders, abstracting whichever stages exist at the time. Engine internals (the preprocessor in P20 Layer 3, multi-backend shaderc in F.BA Phase B) do the real work; P19 is the discoverable verb. Pipeline target: (1) **discover sources** — engine shaders in `<engine_root>/src/cpp/render/bgfx/shaders/*.sc` AND project user shaders in `<project>/shaders/*.{sc,kshader}`. (2) **Preprocess `.kshader` → `.sc`** via P20 Layer 3 preprocessor (when it lands), staging output in `<project>/.cache/generated_shaders/`. (3) **Run shaderc per active backend** (F.BA Phase B), emitting per-backend `.bin` files. (4) **Output paths**: engine shaders → `<engine_root>/src/cpp/render/bgfx/shaders/compiled/{backend}/`, project user shaders → `<project>/shaders/compiled/{backend}/`. (5) **Incremental** via timestamp/hash so re-running is cheap. (6) **Multi-backend**: default = all installed backends; `--backend dx11` filters. **Sequencing**: stand-up the CLI verb (option (a) — thin wrapper over today's `python scripts/compile_shaders.py`) is cheap and unlocks "the user has a verb". As F.BA Phase B + P20 layers land, the verb grows: gains `--backend` flag from F.BA, gains user-shader discovery from P20 Layer 1, gains preprocessor stage from P20 Layer 3. P19 owns the UX; the heavy lifting lives in the other cards. | new |
| P20 | **User shaders / custom shader materials — Slang-native UX** (scope + tech confirmed 2026-05-30) | Today every mesh uses engine built-in `fs_basic`. Target: Godot-like ergonomics (dev writes "what changes", engine wraps with PBR/transforms/lighting/clipping) but implemented natively via **Slang** language instead of a homegrown preprocessor over bgfx `.sc`. Decision: option D from the design discussion — dev writes Slang directly, engine ships Slang modules (`ke_spatial`, `ke_canvas_item`, `ke_particles`, `ke_sky`, `ke_fog`) declaring `interface IMaterial { void vertex(inout VertexInfo); void fragment(inout MaterialState); }` etc. User implements the interface, Slang's generics + interfaces instantiate the engine's main entry point with the user impl. Cross-compile to SPIR-V/DXIL/HLSL/GLSL/MSL is native to Slang; bgfx accepts the bytecode via `createShader()`. **Replaces shaderc in the build pipeline with Slang.** Layers, all eventually shipped: **L1 — `PostEffectNode`** (1 session, scene-tree integration → F.RC2 fullscreen pass). **L2 — `Material.NextPass` chain** (1 session, Godot-style multi-pass per material). **L3 — Slang scaffolding modules + interfaces** (~3 sessions): write `ke_spatial.slang` + sibling modules with `IMaterial`/`ILightModel`/`IParticleShader`/`ISkyShader`/`IFogShader`, migrate ~20 existing engine shaders from `.sc` to `.slang`, wire Slang compiler into the build (replaces `compile_shaders.py` for Slang inputs; keeps it for legacy `.sc` engine shaders during transition). **Sequenced behind F.BA Phase B** so multi-backend output already exists; P19 (`ke build shaders`) is the user-facing verb. Discarded alternatives: (B) Godot-syntax frontend + our parser → Slang (substantial parser maintenance debt), (C) extract Godot's shader compiler (weeks of porting, ongoing fork debt). Slang chosen for: real modules + generics + interfaces (no text-injection brittle preprocessor), official cross-compile, UE5 production validation, future-proof for compute/mesh shaders/RT. Touches: kernel material API (custom program + uniform table variant), render pipeline (`Material.NextPass` loop + custom-program bind + Slang bytecode load via `bgfx::createShader`), shader build pipeline (Slang compiler integration, per-backend output), C# managed surface (`Material.FromShader(shader, uniforms)` + `PostEffectNode` + `ShaderResource`). | new |

P7/P8 are quality-of-life and cheap. P9 rides on collision events (already in spec). P10/P11 are convention/helper additions. P12 needs `Tree.Reload(scene)` which is a whole framework concept. P13 is a 20-line CLI fix once we touch SyncUsings again. P14 shapes how `ke new`/scaffolding subverbs are built whenever they land. P16 is debt that compounds — fix when the user can spare a session to babysit visual validation. P17/P18/P19 are quick wins. P20 is the biggest item; pair with F.BA.

### Tier K — Kernel doctrine audit (what shouldn't be in `src/c/kernel/src/`)

> **Owner observation, 2026-05-30**: "Nosso sistema ECS está até legal, mas poderia ser bem melhor, e ele fere o princípio dos buildblocks com uma implementação no kernel — acho que deveria ser um plugin. Confira outras implementações no kernel que deveriam ser plugins, confira também coisas que ninguém usa lá (alguém usa hash/hash_map? tenho impressão que é legado). Idealmente, kernel nem deveria ter src, ou deveria ter apenas src mínimas, focando principalmente em definir a API em cabeçalhos."

| # | Item | Why | Status |
|---|---|---|---|
| K1 | **Audit `src/c/kernel/src/` and reclassify**: every implementation file should either (a) be a kernel-side primitive nothing else can provide (e.g., `allocator.c` for the allocator vtable spec is borderline-defensible because the engine wires defaults; even that arguably belongs in a "stdalloc" plugin), (b) move to a plugin, or (c) get deleted if unused. **First sweep targets**: `world/ecs.c` (the ECS implementation — should be a plugin per the user's call), `world/world.c` (system graph + world lifecycle — likely a plugin), `common/hash.c` + `common/hash_map.c` (suspect legacy — verify usage; if only ECS uses them, they migrate with ECS into the plugin and don't live in the kernel anymore), `common/array.c` (same drill). | Doctrine: kernel = building blocks, never built blocks. ECS is a *very* opinionated built block — sparse-set storage, `uint64_t` entity, system graph — and forces every binding to inherit those choices. A second binding (Lua per Tier S) might want a different ECS shape, or no ECS at all. | new |
| K2 | **ECS-as-plugin refactor** (lands once K1 audit confirms which kernel src move with it). New plugin `src/cpp/ecs/` (or `src/c/ecs/` if staying C); public header `kernel_engine/ecs/ecs.h` defines the vtable; the existing sparse-set impl moves verbatim. `KernelEngine.Ecs.Native` C# project + DI extension `AddEcsSparseSet()`. Framework consumers (Node, Tree, every component query) take `IEcs` instead of importing kernel ECS symbols directly. **Win**: a future "archetype ECS" plugin can ship alongside `sparse-set` without touching kernel; users pick at composition. **Cost**: the API surface around `Query<T>` is wide; refactor will touch every C# system. Plan multi-commit, fixture-validated. | Same as K1. | new (depends K1) |
| K3 | **Target shape: kernel = mostly headers**. Long-term north star: `src/c/kernel/include/` defines every contract the engine is built on; `src/c/kernel/src/` shrinks to a handful of minimum-viable wirings the engine can't function without (e.g., the default allocator, maybe the logger sink registry, the result code helpers). Everything else is plugin. Each plugin's removal degrades the engine cleanly (no ECS = nodes don't exist = framework opts out) rather than refusing to boot. | Validates the microkernel claim. Today the kernel has substantial built-block implementations masquerading as "building blocks" because they're written in C and live in `src/c/`. | doctrine, not a single card |

> **Why not now**: not a Pong/F.RC2/F.BA blocker; the engine works. Take when the user wants a doctrine cleanup session OR when the Tier S spike forces it (a Lua binding will surface every kernel-side built-block decision the C# binding hides today).

### Tier S — Scripting ABI / language-agnostic node system (post-beta replatforming)

> **REFINEMENT 2026-06-03 (v2) — single framework plugin.** Walked back the per-concept sub-plugin split as over-engineered. Final shape:
>
> - **Contracts live with the kernel's other contracts**: `src/c/kernel/include/kernel_engine/framework/<concept>.h` (node_type_registry, scene_loader, input_actions, resource_cache, scene_tree) + `framework_export.h` with `KE_FRAMEWORK_API` macro.
> - **One plugin** in `src/cpp/framework/` implements all concepts, one CMakeLists, one lib `ke_framework`, multiple `_create()` factories.
> - **External deps stay scoped to the plugin** — tomlplusplus added for `ke_input_actions_create`'s parser, lives in plugin's CMakeLists `target_include_directories PRIVATE`. API consumers don't drag the dep.
> - **Single Framework.rsp** processes all contract headers, libraryPath=`ke_framework`.
>
> This mirrors kernel-plugin pattern (`ke_render` contract → `ke_render_bgfx` plugin) but lets the plugin expose multiple factories because framework concepts are independent primitives. The per-concept-flavor-suffix idea from the aborted refinement below applies only if alternate impls of the same concept appear in the future.
>
> **Status (807 tests verde):** S2.b NodeTypeRegistry, S6 ResourceCache, S7 SceneTree, S4 InputActions all implemented. Added `kernel_engine/kernel/input/key.h` with named GLFW key constants used by S4. Pending: S3 SceneLoader (same TOML pattern as S4), then C# integration phase across all 4 concepts.

> **ABORTED 2026-06-03 — API ≠ plugin.** Mid-Stage-2 owner caught that bundling impls + factories inside `ke_framework` repeated the same mistake the kernel made (API and default impls in one lib, forcing all-or-nothing). New rule for BOTH kernel and framework layers:
>
> - **API layer** `src/c/<layer>/include/...` = vtable contracts only. INTERFACE CMake target — no DLL, just an include path. No factories. No deps.
> - **Plugin layer** `src/cpp/<layer>/<concept>[/<flavor>]/` = impl + factory + its own deps. One library per concept. Mirrors the existing kernel-plugin pattern (`src/cpp/render/bgfx/`, `src/cpp/window/glfw/`).
>
> **Factory naming:** pure-logic plugin = bare `ke_<concept>_create()` in `src/cpp/framework/<concept>/`. Dep-bound plugin = suffix `ke_<concept>_<flavor>_create()` in `src/cpp/framework/<concept>/<flavor>/` where flavor names the dep that justifies it (`ke_input_actions_toml_create`, `ke_render_bgfx_create`, etc.). Factory header lives in plugin's `include/kernel_engine/framework/<concept>[_<flavor>]_create.h`.
>
> **Status:** `ke_framework` is now INTERFACE (header-only). Plugins shipped: `node_type_registry`, `resource_cache`, `scene_tree`. `NativeDependencies.targets` accepts `<NativeDep Include="ke_xxx">` lists. Next plugin: `input_actions/toml/` (S4 with tomlplusplus via vcpkg — the TOML dep stays scoped to that plugin, API layer remains pristine).
>
> **Same doctrine applies to the kernel** (Tier K3 north star "kernel = mostly headers"): `ke_kernel` should also become headers-only with impls in plugins. Deferred until framework migration completes.

> **REFINEMENT 2026-06-02 — kernel vs framework split.** Owner pushed back on "promote to kernel": it conflated ABI-commitment with cross-language reuse, and would drag asset cache + scene tree + scene loader + input actions into the kernel where they don't belong (they're framework-level concerns built on TOP of kernel primitives). New structure introduces a parallel layer `src/c/framework/`:
>
> - `src/c/kernel/` keeps only kernel primitives (allocator, logger, ECS storage, threading semaphores, render/window/audio/scheduler contracts, frame packet). No policy. Pure C ABI, pure C impl.
> - **NEW `src/c/framework/`** mirrors kernel structure exactly: `include/kernel_engine/framework/<concept>.h` contracts + `src/*.c` impl + single `ke_framework` shared lib. **Pure C impl** — these are pure-logic concepts (refcount, lookup, graph traversal, dispatch), no heavy C++ libs needed. Each concept exposes its own C factory in the same lib (`ke_scene_loader_create`, `ke_input_actions_create`, `ke_scene_tree_create`, `ke_resource_cache_create`, `ke_node_type_registry_create`) — same pattern as kernel today (`ke_world_create`, `ke_logger_create`, …).
> - Doctrine: a developer should be able to make a game in pure C using only `src/c/framework/` — no need to reinvent the wheel. Lua/Python/C# bindings get the framework free; they only add language-specific sugar.
> - C# Framework migrates aggressively until it's "binding + sugar". End-state: user code never sees `MeshHandle`, `uint` sentinels, `ke_*` native structs, or `unsafe` blocks. Public surface is `IMesh`, `IMaterial`, `INode`, `ITree`, `IInputActions`, etc., all `IDisposable`.
>
> **Re-classification of S1-S7** (currently all in `src/c/kernel/include/`):
>
> | # | Concept | Belongs in | Notes |
> |---|---|---|---|
> | S1 | `ke_script_component` lifecycle hooks | **kernel** ✓ | stays |
> | S2.a | `ke_variant` (value type) | **kernel** ✓ | stays |
> | S2.b | `ke_node_type_registry` (policy) | **framework** | move |
> | S3 | `ke_scene_loader` | **framework** | move; TOML parser stays plugin-side |
> | S4 | `ke_input_actions` | **framework** | move; built on `ke_input` primitive |
> | S5 | `ke_ecs` storage contract | **kernel** ✓ | stays (impl can still be plugin per K2) |
> | S6 | `ke_resource` cache | **framework** | move; depends on plugin loaders |
> | S7 | `ke_scene_tree` | **framework** | move |
>
> **First mechanical step** when Stage 2 resumes: physically relocate 5 of 7 headers from `src/c/kernel/include/kernel_engine/...` to `src/c/framework/include/kernel_engine/framework/...`, regenerate bindings, fix C# Framework `using`s. Behavior unchanged; doctrine alignment.
>
> **Revised migration strategy — more aggressive (single round per concept):**
>
> 1. Define framework C ABI in `src/c/framework/include/kernel_engine/framework/<concept>.h`.
> 2. Implement in C in `src/c/framework/src/<concept>.c`. NO round-trip back to C# first.
> 3. Regenerate bindings.
> 4. Replace C# Framework class body with thin sugar over the binding — exposes only interfaces, hides handles/pointers.
> 5. Validate: Pong + every example green.
> 6. Delete old C# implementation.
> 7. Next concept.
>
> Justification for skipping the round-trip safety net: Stage 1 already shipped working contract shapes (exercised end-to-end via Pong + Lua spike), so the risk that the C ABI is wrong is much lower than at first design. The safety net becomes "Pong + examples green between every step" — same gate, applied at the C++ checkpoint instead of a bridge checkpoint. One round of code per concept instead of two.
>
> The round-trip pattern (original strategy below) is still the right move for genuinely UNKNOWN contract shapes (concepts not yet exercised). For S1-S7 we've already done that exercise; we don't need to re-pay that cost.
>
> Original 2026-05-28 vision and 2026-05-30 round-trip strategy preserved below for context — the FRAMEWORK SPLIT 2026-06-02 supersedes both on layer assignment and migration speed.

> **Owner vision, captured 2026-05-28.** Original microkernel goal: `C kernel = building blocks`, `any language = Built Blocks (framework)`, `C# = personal sugar helper` — no language privileged. Reality during prototyping: `KernelEngine.Framework` (C#) absorbed `Node`/`Tree`/lifecycle/`SceneLoader`/action layer / Camera2D/Sprite2D/CollisionBody2D/AudioPlayer; C# became implicitly special. **Acceptable for now** because prototyping speed mattered more than ABI purity, but the drift gets paid down once the engine is shippable-game-ready.
>
> **Trigger**: only start after Tier P (UI + CLI + auto-Program) AND the deferred render-pipeline items (clustered forward shading [F.RC3], render-graph [F.RC2], etc. — see Parking lot) are done. Engine must be a viable game-building tool first.
>
> **Goal (corrected 2026-05-30)**: Tier S is **the same doctrine as Tier K, applied to Framework concepts** — NOT "move C# code into the C kernel". Each universal Framework concept gets PROMOTED to a kernel contract (vtable in `src/c/kernel/include/<domain>/<concept>.h`) + a plugin C++ implementation in `src/cpp/<domain>/<impl>/`. C# Framework becomes a binding that consumes those contracts; a future Lua or Python binding does the same. The engine stops having "C# is canonical, others wrap C#" and becomes "kernel defines contracts, every binding is equal".

### Tier S — Safe migration strategy (the round-trip pattern)

**Owner insight, 2026-05-30:** the engine's ABI accepts any language. C# is already implemented end-to-end. To PROVE a Tier S promotion works without sinking weeks of C++ work into a wrong contract shape, the migration goes through a **C# → kernel C ABI → C#** round-trip first — the C# Framework's existing impl IS the body behind the new kernel contract, called from C# via the C# binding. Only AFTER that round-trip validates the contract shape does anyone rewrite the body in C++.

**Per-concept migration sequence (apply to each Tier S item — S1 lifecycle hooks, S2 node type registry, S3 SceneLoader, S4 input actions, S5 ECS, S6 resources, S7 tree):**

1. **Define the kernel contract** — vtable in `src/c/kernel/include/kernel_engine/<domain>/<concept>.h`. Header only. Document semantics.
2. **Regenerate C# bindings** — `python scripts/generate_bindings.py` picks up the new header automatically (rsp already wired). `KernelEngine.Kernel.Native.ke_<concept>` struct + function-pointer fields available in C#.
3. **C# wrapper that satisfies the contract by calling existing C# Framework code** — write `<Concept>Bridge.cs` that allocates a `ke_<concept>*`, fills its vtable slots with `[UnmanagedCallersOnly]` static methods that internally just call the existing C# Framework implementation (e.g., `ke_scene_loader.load = &CallSceneLoaderLoad;` where the body is `SceneLoader.LoadAsync(...)`). Nothing new in C++ yet.
4. **Route Framework consumers through the kernel contract** — anywhere the Framework used to call its internal C# class directly, route through the kernel vtable instead. The C# wrapper bounces it BACK to the same C# code, so behavior is identical, but the indirection layer is now in place.
5. **Validate** — run every example + Pong + the test suite. If anything breaks, the contract shape is wrong and we caught it WITHOUT having lost a single line of C++ work. Iterate on the contract until everything passes.
6. **Only NOW port the impl to C++** — write `src/cpp/<domain>/<impl>/` that implements the same vtable directly in C++. Replace the `<Concept>Bridge.cs` wiring with a call into the C++ plugin's factory.
7. **Delete the old C# Framework impl** — its job is done; the C++ plugin owns the concept now. Framework keeps only the binding-level convenience class.

**Why this matters:**
- **Risk is bounded per step.** If step 3 round-trip breaks, the contract shape is wrong and we iterate cheaply. If step 6 C++ port has a bug, the Framework still has the C# impl living next door for A/B comparison.
- **One feature at a time.** Each concept (SceneLoader, InputActions, ECS, …) goes through 1-7 independently. Pong + every example must stay green between every step. We never "rip everything out and start over".
- **Validates the polyglot claim.** Once a concept lives behind a kernel contract with a working C# round-trip, the path for adding a Lua binding to THAT concept is trivial — Lua impl satisfies the same vtable; the kernel doesn't care which language is on the other side.
- **No big-bang ABI freeze.** Step 5 lets us churn contract shape based on what doesn't fit the C# impl cleanly. Only after the C++ port (step 6) does the contract become "real" enough that breaking it costs work.

**Sequencing within S1-S9:** start with S1 (lifecycle hooks) because it's the smallest concept (just expand `ke_script_component`) — establishes the round-trip pattern with minimal risk. Then S5 (ECS) because it's the highest-impact (also the K1+K2 item) and exposes whether the pattern scales to a wide consumer surface. Then S3/S4 (SceneLoader / InputActions) which are mid-complexity. S6 (resources) and S7 (tree) wait until the pattern is well-worn.

**Receita única, repetida por conceito promovido:**

1. Identifica conceito universal (todo binding/framework precisaria de algo equivalente)
2. Define vtable em `src/c/kernel/include/kernel_engine/<domain>/<concept>.h`
3. Implementa em plugin C++ `src/cpp/<domain>/<impl-name>/` (uma ou mais impls — múltiplos sabores convivem)
4. C# Framework para de implementar internamente e passa a chamar via vtable
5. Próximo binding (Lua, Python, …) ganha o conceito de graça via mesma vtable

**Multiple paradigm contracts coexist:** o kernel pode definir MAIS DE UM contrato concorrente quando ambos forem universais. Exemplo concreto: futuramente o kernel pode ter `ke_ecs` (sparse-set / archetype impls) E `ke_servers` (Godot-style global services) — dev escolhe o paradigma OU usa ambos em partes diferentes da cena. Kernel não opina; oferece contratos.

**Concept extraction targets (não-exaustivo, ordem aberta):**

| # | Concept | Today | Promoted shape |
|---|---|---|---|
| S1 | **Node lifecycle hooks** | `ke_script_component` only has `on_start`/`on_update`. | Expand to `on_awake`/`on_start`/`on_update`/`on_late_update`/`on_destroy`/`on_input`/`on_input_action`. Pure kernel header expansion + script-system update. |
| S2 | **Node type registry + property bag** | C# Activator + reflection populate node properties from `.scene` TOML. | `ke_node_type` registry in kernel + `set_property(entity, key, ke_variant)` — each binding registers its node types by string name; SceneLoader (S3) drives population through this. |
| S3 | **Scene loader** | `SceneLoader.cs` in `KernelEngine.Framework`. | `ke_scene_loader` contract in kernel + plugin impl (`scene-loader-toml` in C++ using existing TOML lib). Framework uses it via the contract — same Lua binding can use the same impl. |
| S4 | **Input action layer** | `InputActions` + `InputActionsLoader` + dispatcher all in Framework. | `ke_input_actions` contract + plugin impl. `.input` parser stays in plugin C++; dispatch + `on_input_action` callback via contract. |
| S5 | **ECS** (already pre-planned as Tier K1+K2, but logically also a Tier S item) | `world/ecs.c` in kernel src. | `ke_ecs` contract in kernel header + `ecs-sparse-set` plugin (current impl). `ecs-archetype` future. See [Tier K] above. |
| S6 | **Resource family** (Mesh/Material/Sound/Font/…) | `Resource.cs` family in Framework with ref-counting + cache. | `ke_resource` contract + plugin impl. Cross-language handle + lifecycle without re-doing the cache in each binding. |
| S7 | **Tree / scene graph** | `Tree.cs` in Framework. | `ke_scene_tree` contract + plugin impl. Or stays Framework-side if "tree organization" is acceptable as a binding choice (open). |
| S7.5 | **Port `KernelEngine.CSharp` plugin to C++** — `CSharpSceneLoader` vira `ke_scene_loader` implementado em C++ (`src/cpp/scene_loader/toml/`); `NodeTypeRegistry` vira `ke_node_type_registry` em C++. C# Framework passa a consumir via vtable, não via impl própria. Pré-req para S8: sem isso Lua teria que depender de código C# para carregar cenas. |
| S8 | **Reescrever Pong em Lua puro — sem C# nenhum.** Binding mínimo (LuaJIT + sol2 ou FFI direto). Cada vez que Lua precisar de algo que está preso no Framework C# = contrato faltando na API C → promover para kernel. O que sobrar no Framework que Lua também precisou = candidato a promoção. O que Lua não precisou = açúcar C#, fica no Framework. Começa mínimo (janela + update + quad), só depois porta o jogo completo. |
| S9 | **ABI documentation + stabilization** — once published, refactoring freedom shrinks. Commit after the Lua port validates the contract shapes. |

**Spike first (2-3 weeks) before committing the full sequence:** S1 only (lifecycle hooks expansion) + minimal Lua binding that overrides `on_start`/`on_update` on a single Pong script (paddle or ball). Don't promote SceneLoader/InputActions yet. Just prove cross-language script dispatch works with acceptable latency through the kernel contract. Then decide whether to invest in S2-S9.

**Open design questions to resolve during the spike:**
- Resources cross-language: ref-counted C# class today; Lua userdata with `__gc`; Python ctypes-managed. The `ke_resource` contract (S6) needs neutral handle + lifecycle.
- DI cross-language: `ActivatorUtilities` is .NET-specific. Each binding needs its own DI resolution from ctor signature in its language.
- Generics + enums: `IInputActionReader<TEnum>` is .NET-only. Kernel `ke_input_actions` (S4) must be non-generic (lookup by string-name); each binding adds typed overlay on top.
- Hot-reload: now becomes interesting per-binding; kernel needs "destroy all scripts of this type, reinstantiate with new factory" primitive.

### Tier E — Editor (CLI today, GUI later) — agnostic core + per-framework modules

> **Owner doctrine, 2026-05-30**: The editor (CLI now, GUI later — chapter 18) must be agnostic of any specific framework/language. It manages **kernel-level concepts** (Project file, module catalog, scenes, input actions, assets). Per-framework knowledge (how to scaffold a C# script, how to edit `Program.cs`, how to manage a `.csproj`) lives in **editor modules** that plug into the core. When a Lua binding lands, a `editor-lua` module plugs in and the editor learns to scaffold Lua scripts — no core change.

**Today's state vs target:**

- `KernelEngine.Cli` does have C#-specific bits (Roslyn in `ProgramCsSync.cs`, csproj XML edits in `CsprojEditor.cs`, module discovery rooted at `src/csharp/*/Modules/*.ke-module`). Justified by "only C# binding exists today" — but the shape matters.
- **Acceptable**: those C# bits all live in clearly-named files (`ProgramCsSync.cs`, `CsprojEditor.cs`) inside `KernelEngine.Cli`. When Tier S lands, those become an extractable `KernelEngine.Cli.Csharp` package; the rest of `KernelEngine.Cli` (Project file IO, manifest, scene/input verbs) stays framework-agnostic.
- **Forbidden going forward**: pulling `Microsoft.CodeAnalysis.CSharp` into any new file that ISN'T explicitly C#-module work. Any new "editor verb" (scene management, asset import, input action editing) should manipulate kernel-level data only.

| # | Item | Status |
|---|---|---|
| E1 | **Soft-segregate** `KernelEngine.Cli` internally — folder structure separates `Core/` (Project + module catalog + scene/input/asset verbs) from `Csharp/` (ProgramCsSync, CsprojEditor, .NET-specific scaffold). No package split yet (premature with one binding). Establishes the boundary so refactor is mechanical when Tier S lands. | new |
| E2 | **Module discovery beyond `src/csharp/`** — today `.ke-module` files are discovered by walking `src/csharp/*/Modules/`. The "discover plugins" mechanism should accept multiple roots OR plugin entries that point to non-C# subtrees. When a `KernelEngine.Lua` plugin ships in `src/lua/` or `src/cpp/lua-binding/`, its `.ke-module` files should be findable without CLI core change. | new (depends Tier S spike) |
| E3 | **Editor module manifest** — when GUI editor lands (chapter 18), it loads "editor extension modules" much like the runtime loads plugins. `editor-csharp` adds C# script editing + Roslyn-backed refactors; `editor-lua` adds Lua scaffolding; `editor-tilemap`, `editor-shader-graph` etc. become third-party-addable. | doctrine, separate card later |
| E4 | **Don't plant new framework-coupled dependencies in CLI core** — invariant rule. Any new feature that "scaffolds a script" or "edits a project file in a language-specific way" goes in a `Cli.<Framework>` folder (today: `Cli.Csharp`). | rule, always-on |

> **Why not now**: not blocking anything. The shape is small enough today (single C# binding) that we can refactor mechanically when needed. Registered so the discipline is preserved when adding new CLI verbs.

### Tier T — Testing backlog

> **T0 — DONE (2026-06-02)**: coverage pipeline rewritten from scratch as `scripts/coverage.py`. Source-based Clang instrumentation (`-fprofile-instr-generate -fcoverage-mapping`) replaces `--coverage`/gcov, killing the `.gcda` corruption spam. CMake instruments all `src/` + `tests/` targets globally via `add_compile_options` when `KE_COVERAGE=ON` — no per-target opt-in, new plugins are covered automatically. `cmake/Coverage.cmake` deleted. Pipeline: build → `ctest` (collects `.profraw`) → `llvm-profdata merge` → `llvm-cov export -format=lcov` → `dotnet test --collect:"XPlat Code Coverage"` → ReportGenerator → custom layered summary (L1 kernel / L2 plugins / L4 framework + critical-gap flagging). Subcommands: `run` (default), `clean`, `report`. Everything lives under `build/coverage/`.

> Coverage pipeline audited 2026-05-31: 5 native plugins (`audio`, `dev_platform`, `physics`, `task_scheduler`, `text`) were not instrumented by `KE_COVERAGE` and not captured by `gcovr`. Fixed in commit `ff58ef4` — `dev_platform.win32` jumped 0% → 100% (tests already existed; cobertura was being discarded). Items below are the remaining gaps.

| # | Item | Status |
|---|---|---|
| T2 | **`tests/cpp/test_task_scheduler.cpp`** uses a mock scheduler in-place (`make_sync_scheduler()`) — exercises only the contract semantics, never loads the real `ke_task_scheduler_enki` plugin. `src/cpp/task_scheduler/enki/` shows 0% native coverage as a result. Add a parallel integration test that instantiates the real enki scheduler via `ke_task_scheduler_enki_create()` and runs dispatches. | new |
| T3 | **C# projects with non-trivial logic but no `.Tests`**: `KernelEngine.Cli` (Roslyn Program.cs sync, TOML scaffolding, ke-module discovery) and `KernelEngine.CSharp` (CSharpSceneLoader, NodeTypeRegistry, ISceneTree). Both are invisible to coverage. Create dedicated `.Tests` projects (convention: `KernelEngine.Framework.Tests`). | new |
| T4 | **`KernelEngine.Configuration`** — visible at 0%. TOML binder + ServiceCollectionExtensions. Coverage added via expansion of `KernelEngine.Kernel.Tests` (too small to justify its own project). | new |
| T5 | **Thin-shell plugin C# projects** (factory + 1 extension method): `Asset.Assimp`, `Asset.StbImage`, `Audio.MiniAudio`, `DevPlatform.Win32`, `Physics.Box2D`, `Render.Bgfx`, `Render.Core`, `TaskScheduler.Enki`, `Text.StbTrueType`, `Window.Glfw`. No dedicated `.Tests` warranted — exercised transitively by any example. Coverage gap that matters is the native plugin under `src/cpp/`, tracked separately (T2 + T7). | doctrine |
| T6 | **Empty leftover folder**: `src/csharp/KernelEngine.Contracts/` contains only a `.lscache` (folder was renamed to `KernelEngine.Kernel.Abstractions` in commit `82905a1`). Safe to `git rm -r`. | trivial cleanup |
| T7 | **Mock-only-tests audit**: every plugin under `src/cpp/` that ships a `<plugin>_create()` factory but shows 0% native coverage despite having a C++ test in `tests/cpp/`. Likely candidates: `test_render_bgfx.cpp`, `test_window_glfw.cpp`. Same root as T2 — replace mock-in-place with integration tests that load the real plugin. | new |
| T9 | **`InternalsVisibleTo` debt in `KernelEngine.Kernel` and `KernelEngine.Framework`** — both csprojs expose internals to their `.Tests` projects (`Kernel.csproj` to three test assemblies, `Framework.csproj` to one). Each `internal` member that tests reach via this hatch needs a per-class decision: (a) promote to `public` if it's effectively part of the API surface and the only thing keeping it internal was caution (often the case — see `TomlOptionsBinder` precedent in `KernelEngine.Configuration`, made public 2026-06-02), (b) keep `internal` and test through a public consumer instead, or (c) accept the visibility hatch with a documented justification. Audit class-by-class; goal is to drive the count of `InternalsVisibleTo` lines in each csproj to zero where possible. Not urgent — pre-existing debt, not a fresh regression. | new |
| T8 | **Native coverage pipeline was broken** (gcov-based, dropped 0%-coverage modules silently). Resolved by T0's full rewrite to source-based Clang instrumentation. | DONE 2026-06-02 |

### Parking lot — explicitly post-beta

- Visual editor GUI (M4) — chapter 18 prepares the lib; the GUI itself waits.
- **Render-graph + GPU-compute primitives ([F.RC2])** — universal extensibility surface for graphics techniques. SSAO/FXAA/TAA/SSR/DoF become registered passes; built-in bloom/SSAO/tonemap re-expressed through it (kills hardcoded view chain).
- **Clustered forward shading ([F.RC3])** — current brute-force caps at ~64 point / 48 spot; surplus silently dropped. Naturally rides on F.RC2.
- **GPU instancing + `MultiMeshRenderer` ([F.RC1])** — required for grass/crowds/particles at scale.
- Skeletal animation, networking, particles, save/load framework, joints/raycasts on top of physics layer (chapter 24 §8).
- MCP server for agents (CLI piping is enough for now — chapter 19 §9.2).
- **[GAMEPLAY-CONTRACTS] Marketplace-compatibility contracts (Unreal-vocabulary-inspired, non-priority)** — long-term direction for enabling a kit/marketplace ecosystem (the Unreal asset-flip model, done right). Strategy: **copy the vocabulary, not the form** — borrow Unreal's familiar naming (`ICharacter`, `IDamageable`, `IInteractable`, `IHealthSource`, `IInventoryHost`, `IMovementComponent`, etc.) so devs coming from UE feel at home, but ship them as **small composable interfaces**, NOT one mega-`ACharacter` aggregate. `ICharacter` becomes a marker that bundles the small contracts; a stealth kit can implement only `IDamageable + IInteractor` and still compose with everything else — no "must inherit from `MasterCharacter`" trap that plagues the Unity Asset Store. Two kits from different authors compose because they speak the same gameplay-layer vocabulary. **Why not now**: contracts must be *extracted from real use*, not invented up-front. We need varied gameplay (Pong + Platformer + RPG mini + Shooter mini) before honest abstractions emerge — premature contracts either over-constrain (museum of unused interfaces) or under-constrain (`Dictionary<string, object>` masquerading as types). Bevy has been wrestling with exactly this for years. **When**: M3–M5 phase, after several non-Pong examples force the natural shape; freeze + semver-major-commit at M5 when targeting a marketplace launch. **Legal caveat**: API names like `TakeDamage` aren't copyrightable (Oracle v. Google), but verbatim copy of Unreal headers + docstrings is risk. Inspiration via naming + semantics yes, copy-paste no — write the contracts deliberately through our own lens. Out of scope until then: no new interface lands in `KernelEngine.*` framework with "I-prefix gameplay contract" intent before the example coverage justifies it.
- **[F.GPU] GpuDevice impl swap — deferred decision** (2026-05-30). Owner is satisfied with bgfx for now; ray tracing isn't a near-term priority and Slang covers all planned shader needs through bgfx's `createShader(bytecode)`. The `GpuDevice` abstraction in `src/cpp/render/contract/include/gpu_device.hpp` makes the swap a contained project (~5-6 sessions: vendor lib + new `<lib>_device/` plugin + GpuDevice impl + smoke examples + paridade). **Leading candidate when trigger fires: The Forge (Confetti FX)** — AAA-validated, RT + mesh shaders native, Vulkan/D3D12/Metal backends, Apache 2.0 with NOTICE attribution. Runner-up: Diligent Engine (closer API shape to bgfx, slightly easier swap, also RT-capable). Trigger conditions: (a) a real consumer demands hardware RT, (b) bgfx maintenance stalls or critical bug we can't get fixed upstream, (c) we hit mesh shader / work graph / future-API requirements bgfx doesn't expose. Until then: no work.

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

##### [OBS.7] Directional shadow not visible in example 06_shadow_map (RESOLVED 2026-05-30)
- **Tags**: `bug`, `render`
- **Symptoms**: `dotnet run --project examples/csharp/06_shadow_map` renders the scene + lighting normally but the **projected shadow of the cube on the ground plane is absent**.
- **Root cause (bisect-confirmed)**: commit `16957b2` (2026-05-27 "Camera2D + Sprite2D + Ortho handedness fix") flipped `ViewProjection.Ortho` from LH (positive M33) to RH (negative M33) so view-z in [-near, -far] maps to NDC z in [0, 1]. But `ViewProjection.LookAt` was still secretly LH (storing `+f` in the z column instead of `-f`) despite a comment claiming RH. The shadow camera's view × proj therefore mapped origin to view-z = +25 — *outside* the new RH frustum (which expects negative view-z). Result: shadow camera saw nothing → R32F shadow target stayed at its clear value (1.0 far) → `coord.z - 0.005 > 1.0` was always false → `ComputeShadow` returned 1.0 (no shadow) for every fragment.
- **Fix (commit ec5678f)**: make `ViewProjection.LookAt` actually RH by negating `f` in its z-column slots (M13/M23/M33) and the corresponding translation (M43 = `+dot(f, eye)` instead of `-dot(f, eye)`). ShadowRenderSystem now lands origin at view-z = -30.6 (inside the [-0.1, -50] frustum). Test `LookAt_ProducesCorrectViewMatrix` updated for the new semantics. Sole non-test consumer of `ViewProjection.LookAt` was ShadowRenderSystem (CameraRenderSystem uses `Matrix4x4.Invert(WorldMatrix)`), so the change is contained — confirmed visually on example 06 + Pong.
- **Bisect record**: good `b4f4a99` (2026-05-27 20:54) → bad `16957b2` (21:26). 79 commits searched in 5 iterations once cache poisoning was fixed (cmake build/, build/native/, dotnet bin/obj, compiled shaders all had to be wiped per checkout — see CLAUDE.md PreserveNewest note + new working rule [[feedback_clean_rebuild_per_bisect]]).

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

### Tier H — Hygiene & instrumentation carry-overs

Small carry-over items from the BLOCK 5 cleanup pass. Larger archived completions live in [Done.md](Done.md).

| # | Item | Detail |
|---|---|---|
| H1 | **[Y.10] Bindings-drift detection in CI** | Compare mtimes of `src/c/kernel/include` + plugin public headers vs `Generated/*.cs`; fail build if headers are newer. Prevents Bug 1.25-style P/Invoke drift. |
| H2 | **[Y.2] `LogErr` C++ helper** | Macro that logs `__func__` + detail before returning `KE_ERROR_*`. Surfaces silent failures in `bgfx_gpu_device.cpp` / `core_renderer.cpp`. |
| H3 | **[Y.3] Debug logging in initialization** | Trace-level logs for shader paths, file existence, GPU caps during `BgfxGpuDevice::Init`. Diagnoses startup failures without a debugger. |
| H4 | **[Y.5] Audit Framework result discards** | Sweep `KernelEngine.Framework` for `_ = ...` patterns and bare result returns; replace with `KernelException.ThrowIfFailed`. |
| H5 | **[U.1] VSync configuration** | Wire `WindowConfig.vsync` through `bgfx::reset`; uncapped FPS for benchmarking. |
| H6 | **[L] Read/write set enforcement (debug)** | `ke_access_record` in `ke_ecs_registry` debug-only; scheduler validates declared access sets post-wave; assert if a system writes a component it declared read-only (Bug 1.13). |

### Tier TH — Threading hardening

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

#### [DEADLOCK-FREE] Concurrency by Construction — make cross-thread bugs unrepresentable
- **Why**: The Pong tela-branca regression (2026-05-XX) was a `CreateMaterialAsync().GetAwaiter().GetResult()` inside `MeshRenderer.Start` — sim blocked on render while render waited for sim's frame packet. We fixed it by pre-resolving materials at load time, but that's discipline, not architecture. Nothing prevents the next contributor (including us) from chaining the same wait edge in a new feature. The doctrine is: **the engine must be a system where deadlocks and cross-thread data races are not in the alphabet** — not "easy to avoid", but impossible to express without writing something visibly named `Unsafe.*`.
- **What**: Codify and enforce a three-pillar threading contract across the engine's threaded surface.
    1. **Forward-only queues**: communication between the three named threads (`ke.main` → `ke.sim` → `ke.render`) is one-directional and snapshot-based. No thread holds a reference to the next thread's mutable state. Crossings happen via single-producer queues that transfer ownership of an immutable snapshot. Worker threads (enkiTS pool) are stateless leaves — `await Task` is legal there and only there.
    2. **Phantom thread tokens**: `SimContext` and `RenderContext` are `ref struct`s. Sim-only methods take `in SimContext`; render-only methods take `in RenderContext`. The token's `internal` constructor is only callable from `Application`'s loop bodies. `ref struct` semantics make the tokens unstorable / uncapturable / unleakable. Calling a render-only method from sim becomes a compile error, not a runtime bug.
    3. **API by absence**: sim-thread code has no field, no `Services.Resolve`, no static accessor that yields the concrete `IRenderer`. The only thing it can reach is `IRenderCommandQueue.Enqueue`. If you can't *name* the renderer in scope, you can't call into it — sync or otherwise.
- **Acceptance**:
    - Pillar 1: every cross-thread write goes through a typed queue+snapshot; there is zero `lock` / `Monitor` / `Mutex` shared between named threads. Documented in `docs/Reference/08 - Multithreading.md`.
    - Pillar 2: `SimContext` and `RenderContext` exist; every public method on `Node`, `World`, `Renderer`, `ResourceManager` that runs on a specific thread takes the matching token; renaming `Update(float dt)` → `Update(in SimContext ctx, float dt)` is the migration.
    - Pillar 3: `IRenderer` is not in the DI container slot reachable from a `SimContext` method. `ResourceManager.CreateMaterialAsync` / `CreateMeshAsync` / etc. return concrete handles synchronously (sentinel until render fulfills); no `Task` over a render-thread crossing.
    - **Roslyn analyzer** flags `.Result`, `.GetAwaiter().GetResult()`, `.Wait()`, `Semaphore`, `Monitor.Enter`, `lock` inside any method taking `SimContext` or `RenderContext`. Escape hatches live in a `KernelEngine.Unsafe.*` namespace.
    - The Pong deadlock is provably re-inexpressible: attempting to write `MeshRenderer.Start` with `CreateMaterialAsync().GetResult()` is a compile error.
- **Steps**:
    1. Pin the doctrine — write `docs/Reference/08 - Multithreading.md` § "Deadlock-Free by Construction" with the three pillars and the worker-vs-named-thread rule.
    2. Define `SimContext` / `RenderContext` ref structs in `KernelEngine.Kernel`. Application fabricates them per frame.
    3. Refactor `ResourceManager` so create-methods return synchronous handles (sentinel + render-fulfilled). Drop `Task<Material>` / `Task<Mesh>` from the cross-thread surface; keep `Task` only on disk-IO loaders (`IImageLoader.LoadAsync`, `IModelLoader.LoadAsync`) since those run on workers.
    4. Walk every `Node` subclass and migrate `Update(float dt)` → `Update(in SimContext ctx, float dt)`. Same for `OnStart` / `LateUpdate`.
    5. Remove `Application.Renderer` (or any path) from the sim-thread-reachable surface. Sim only sees `ISceneWriter` / `IRenderCommandQueue`.
    6. Ship the Roslyn analyzer in a `KernelEngine.Analyzers` package referenced by every framework consumer csproj.
    7. Bisect-test by reverting the Pong material-pre-resolve fix — the analyzer + types must reject the old `Start` body at compile time.
- **Out of scope**: changes to the worker pool (enkiTS stays as-is); changes to bgfx multithread mode (orthogonal); changes to `KernelThread.AssertCurrent` debug assertions (those become a runtime backstop for the worker→named-thread direction, where types can't reach).
- **Risk / cost**: high churn — every `Update` override in framework + examples + Pong needs its signature changed. Worth it: the entire category "concurrency bug" exits the engine's failure modes. Estimate: 1-2 sessions for pillars 1+3, +1 for the analyzer (Roslyn boilerplate), +1 for the full migration sweep.

#### [N] Profiling & Trace Observability
- **Why**: Diagnose frame spikes and wave imbalances without guesswork (Bug 1.15).
- **What**: Per-thread ring buffer flushing to Chrome Trace JSON.
- **Acceptance**: Generating `ke_trace.json` showing 3 threads + workers timeline.
- **Steps**:
    1. Implement `ke_profile.h` macros.
    2. Add instrumentation to key engine milestones.
    3. Implement JSON exporter.

### Roadmap — M3 onward

Milestone-level capability snapshot (M3 gameplay categories, M4 editor, M5 networking + advanced rendering) lives in [`Roadmap.md`](Roadmap.md). The cards previously sitting inline here have been consolidated there; per-milestone work re-enters this Kanban as actionable tier cards once it's the next thing to do.

## ✅ Done

Archived to [`docs/Done.md`](Done.md). The Kanban no longer carries finished work — new completions append there directly.

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
