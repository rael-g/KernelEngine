# 14 — Editor, CLI & Agent Layer

> **Status**: 📋 Vision document. Nothing in this chapter is implemented yet. It captures the doctrine that constrains *how* the editor and tooling layer will be designed when work begins.

## 1. Thesis

The way software is authored is changing. Humans are increasingly not the ones typing. The dominant author of new code is, and will be, an AI agent. The game industry trails this curve by several years — Unreal and Unity remain editor-first because their cores were never designed to be driven by anything except their own GUI. **KernelEngine will be designed the opposite way from day one.**

Concretely: **the engine is a library; every editor — GUI, CLI, agent — is just another client of that library.** No editor knows anything the library does not. There is no privileged "editor mode" in the engine. The same calls that move a node in the GUI move it from a CLI command move it from an agent's tool call.

This is not a novel idea. `git`, `kubectl`, `docker`, `dotnet`, `cargo` all work this way. Game tooling has historically been the exception because no engine treated *programmatic editing* as a first-class use case. We will.

## 2. The library-first principle

```
┌──────────────────────────────────────────────────────────────┐
│  Frontends (interchangeable; consume the same API)            │
│  • KernelEngine.Editor.Gui   — eventual graphical editor      │
│  • KernelEngine.Editor.Cli   — `ke` command-line tool         │
│  • KernelEngine.Editor.Agent — IPC/MCP surface for AI agents  │
├──────────────────────────────────────────────────────────────┤
│  KernelEngine.Editor                                          │
│  Operations: CreateProject, OpenProject, CreateScene,         │
│  AddNode, SetProperty, SaveScene, RegenerateBindings, etc.    │
│  Every editor operation goes through this layer.              │
├──────────────────────────────────────────────────────────────┤
│  KernelEngine.Framework + Kernel                              │
│  Runtime engine (already exists).                             │
└──────────────────────────────────────────────────────────────┘
```

### Why the lib comes before any UI

- A frontend that wants a feature **cannot ship it without exposing it in the lib first**. This single rule keeps the lib complete and prevents the trap Unity/Unreal fell into (editor-only features that scripting cannot reach).
- A new frontend (web, voice, VR, agent) becomes a thin wrapping job, not a re-implementation.
- Testing the editor surface is just testing a library — no UI automation required.

### CLI as the reference frontend

The CLI will be **the most complete** of the three frontends, because:
- It is also what AI agents drive (until they get a structured IPC surface).
- It is the lowest-friction surface for the author of the engine itself to dogfood the editor.
- Anything the CLI cannot do, the GUI cannot do — by construction.

Command style follows the `dotnet` / `cargo` convention:

```
ke new project MyGame                  # scaffold a project
ke new scene Level1                    # create a scene file
ke add node MeshRenderer --parent Root --name Cube --to scenes/Level1.scene
ke set property scenes/Level1.scene Cube.MaterialHandle = res://materials/red.toml
ke run --headless --frames 60 --trace run.jsonl
ke build --target win-x64
```

Verb-first, target-second, options third. Composable in shell pipelines.

## 3. Agents are first-class clients

The CLI handles the agent case today; the agent-native surface (an MCP server, or a long-running IPC daemon) will come later. Both are clients of `KernelEngine.Editor` — neither is privileged.

The non-negotiable property: **an AI agent must be able to develop a game in this engine without a human present**. That means the agent needs to:

1. **Author and modify content** — scenes, nodes, resources, code. Already covered by the CLI.
2. **Run the game and observe what happened**. This is the hard part. The rest of this chapter is about it.

## 4. The five layers of agent visibility

Agents do not have eyes. To give them something like sight into a running game, we need machine-readable observation surfaces. There are five layers, ordered cheapest to most expensive. The first two cover ~80% of real debugging.

### Layer 1 — Structured event log

JSON-lines on stdout (or a file when headless), not human-prose log lines. Every event has a `kind`, a `frame`, structured payload, and a severity.

```jsonl
{"frame":120,"kind":"collision","entities":[47,12],"point":[3.2,0,5.1]}
{"frame":120,"kind":"asset_loaded","path":"res://meshes/cube.glb","duration_ms":47,"vram_kb":1024}
{"frame":121,"kind":"frame_stats","fps":58.4,"draw_calls":142,"triangles":48003}
{"frame":122,"kind":"shader_compile","backend":"vulkan","program":"pbr","status":"ok","duration_ms":12}
```

The taxonomy is the design effort — `kind` is a closed enum that grows over time. Levels (`debug`, `info`, `warn`, `error`) filter what the agent ingests.

Builds on top of `ke_logger` + sinks (already exist). New work: a JSON-lines sink and a small event vocabulary.

### Layer 2 — Declarative world introspection

The agent should be able to ask *"what is the world right now?"* and get back structured data, not text.

```
ke inspect scene --query "nodes where type = MeshRenderer"
ke inspect node Cube --include components,transform,children
ke inspect frustum                          # what the active camera sees
ke inspect resources --kind material        # all loaded materials
```

This is `git status` for the running world. It rides directly on the ECS — `world.Query<T>()` already exists internally; serializing the result to JSON is the work.

Critically, this is **the loop**: agent edits with CLI → agent runs game headlessly → agent inspects state → agent edits again. No screenshots needed for most gameplay work.

### Layer 3 — Screenshots / framebuffer dumps

`engine.screenshot(path)` and a `--auto-screenshot` flag dumping a PNG every N frames. The agent feeds the PNG through a vision model and asks structured questions ("is the shadow aligned with the light? does the metal sphere look metallic?").

Expensive (PNG encode + vision model latency + tokens). **Only mechanism that can catch visual bugs** — shader miscompiles, lighting setup mistakes, render-state regressions. Do not turn on by default; opt-in per-test or per-investigation.

Hook point: `FrameSync` already isolates the render thread; a "screenshot sink" plugs in between submit and present.

### Layer 4 — Headless + deterministic replay

```
ke run --headless --seed 42 --frames 600 --trace run.jsonl
```

Stubbed window (no GLFW), offscreen rendering (bgfx supports it), full event trace + state snapshots written to disk. The agent reads the trace offline; the game does not need to be live while the agent thinks.

Same seed → same trace, every time. This is what unlocks CI for game logic: baseline trace lives in the repo, divergence is the test failure.

Demands: a window-stub plugin, deterministic timekeeping (no `DateTime.Now`, no unseed `Random`), a trace writer.

### Layer 5 — Inline assertions

```
ke assert "entity matching 'Player' visible within 100 frames"
ke assert "no warnings of kind shader_compile"
```

Property tests for runtime behavior. Failures emit Layer 1 events; pass with no extra noise. Built on Layer 2 (introspection) + Layer 4 (deterministic runs).

## 5. Design principles for agent visibility

These constrain *how* the five layers are built, beyond the layers themselves:

### 5.1 Reproducibility is non-negotiable

Anything an agent observes must be reproducible by re-running with the same inputs. Concretely:
- Time is injected (no direct `DateTime.Now` in engine code).
- Randomness is seeded (the engine owns the default RNG and exposes it).
- Threading must not change observable order (it can in performance terms; not in logged events).

This costs perf; pay it. An agent that cannot reproduce a bug cannot fix it.

### 5.2 Observation is asynchronous

Agents do not watch frame 120 while it happens. They read the trace afterward. This shifts what to log:
- Prefer cumulative summaries to per-event spam.
- Surface "what changed since last snapshot" rather than full state every frame.
- Snapshots cheap to ingest beat firehoses that blow the context window.

### 5.3 Context budgets are real

If each frame writes 5 KB of JSON, 60 seconds is 18 MB — half a Claude context. The right interface is *queryable*, not *streaming*:

```
ke trace run.jsonl --kind collision --frames 100-200
ke trace run.jsonl --kind warn --tail 50
```

The agent asks; the trace responds with bounded chunks. A full dump is an option, not the default.

### 5.4 Lib operations are runtime-aware

Some editor operations (CreateProject, GenerateBindings, ScaffoldAsset) are *build-time only* — they have no runtime equivalent. Others (AddNode, SetProperty, SaveScene) work both on-disk and on a live world.

This split lives in the API: `KernelEngine.Editor.Authoring` vs `KernelEngine.Editor.Runtime`. A frontend wires both as needed.

## 6. Implementation order

Roughly in priority:

1. **Layer 1 — structured JSONL events.** Cheapest, highest ROI. Direct extension of existing logger. Decide event taxonomy first.
2. **Project file format + CLI scaffold.** `ke new project`, `ke new scene`. Forces serialization (chapter 15) to be designed and used end-to-end.
3. **Layer 2 — introspection API.** `ke inspect`. Forces the ECS to expose a serializable view; falls out naturally from existing queries.
4. **Layer 4 — headless mode + deterministic time.** Unlocks CI. Largest single piece of work.
5. **Layer 5 — assertions.** Trivial once 1, 2, 4 exist.
6. **Layer 3 — screenshots.** Last, because expensive and rarely needed once the above exist.
7. **GUI editor.** Last frontend. By the time it ships, the lib is complete and the GUI is a viewport on top of CLI/agent operations.

## 7. What the editor lib is NOT

- **Not a level-editor renderer.** Rendering scenes for an editor viewport is just a game running in headless-but-display mode. The runtime renderer handles it.
- **Not where business logic lives.** Operations are CRUD on the project/scene/asset model. Game logic stays in user code.
- **Not coupled to any frontend.** If `KernelEngine.Editor` depends on Avalonia/ImGui/anything visual, the design is wrong.

## 8. Cross-references

- Serialization formats consumed by all three frontends: [15 - Serialization & Project Files](15%20-%20Serialization%20%26%20Project%20Files.md).
- The runtime engine the editor drives: [06 - Framework](06%20-%20Framework.md), [03 - C Kernel](03%20-%20C%20Kernel.md).
- The doctrine that motivates "lib > frontend": [13 - Extensibility & Universality](13%20-%20Extensibility%20%26%20Universality.md).
- Roadmap entries for editor/CLI/agent work: [11 - Roadmap & Vision](11%20-%20Roadmap%20%26%20Vision.md), [Kanban](../Kanban.md).
