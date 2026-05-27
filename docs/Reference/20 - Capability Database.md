# 20 — Capability Database

> **Status**: 📋 Architectural decision. Not implemented. This chapter specifies the build-time artifacts that let tooling (CLI, GUI editor, AI agents, future non-C# implementations) discover what the engine exposes — without runtime reflection and without per-tool hardcoding.

## 1. The problem

A frontend needs to answer questions like:

- *"What node types can I instantiate in this project?"*
- *"What rendering backends are available?"*
- *"What does the `Scene.AddNode` operation accept and return?"*

Naive answers are all wrong:

- **Runtime reflection** — works in dev, but breaks AOT/mobile, requires the C# runtime, slow on cold start, invisible to non-C# tools.
- **Hardcoded knowledge in each frontend** — drifts immediately. CLI and GUI start disagreeing about what `MeshRenderer` properties exist.
- **Documentation as the source** — outdated by the second commit.

The correct answer is a set of **build-time data artifacts** that every frontend reads. The engine generates them deterministically; everything else consumes them.

## 2. The three databases

| File | Describes | Generated from |
|---|---|---|
| `class_database.toml` | Every `Node`-derived type + its serializable properties. | C# reflection (dev) or source generator (AOT) at build time. |
| `plugin_database.toml` | Every registered plugin (window, renderer, audio, asset, input). | Per-plugin `plugin.toml` manifests, aggregated at build. |
| `operation_database.toml` | Every Editor Lib operation + arguments + return shape. | Source generator scanning `KernelEngine.Editor` interfaces. |

All three live in `build/capabilities/` (configurable). All three are TOML for the same reason scenes are (chapter 15): readable diffs, language-agnostic parsing, human-editable as a last resort.

## 3. `class_database.toml`

Already introduced in [17 - Scene & Node Serialization §4](17%20-%20Scene%20%26%20Node%20Serialization.md#4-the-class-database--schema-as-data-not-code). Restated here for completeness:

```toml
[[type]]
name      = "MeshRenderer"
namespace = "KernelEngine.Framework"
extends   = "Node"
abstract  = false

  [[type.property]]
  name    = "MeshHandle"
  kind    = "MeshHandle"
  default = 0

  [[type.property]]
  name    = "MaterialHandle"
  kind    = "MaterialHandle"
  default = 0

[[type]]
name      = "MyGame.Boss"
extends   = "Node"

  [[type.property]]
  name    = "Hp"
  kind    = "float"
  default = 100.0
```

**Consumers:**
- Scene loader (knows what types are valid, what properties exist).
- CLI: `ke add node <type>` completion, `ke describe types`.
- GUI editor: populates "Add Node" menu and the inspector panel.
- Agent: validates a scene edit before committing it.

## 4. `plugin_database.toml`

Lists every plugin available to the project. The project's `Project` `[runtime]` section names plugins; this DB describes what's behind those names.

```toml
[[plugin]]
name     = "bgfx"
category = "renderer"
assembly = "KernelEngine.Render.Bgfx"
native   = "ke_render_bgfx"

  [plugin.capabilities]
  backends = ["vulkan", "d3d12", "metal", "opengl"]
  features = ["pbr", "shadows", "post_fx", "compute"]

  [[plugin.option]]
  name    = "shader_path"
  kind    = "string"
  default = "shaders"

[[plugin]]
name     = "glfw"
category = "window"
assembly = "KernelEngine.Window.Glfw"
native   = "ke_window_glfw"

  [plugin.capabilities]
  platforms = ["win", "linux", "mac"]

  [[plugin.option]]
  name    = "fullscreen"
  kind    = "bool"
  default = false

[[plugin]]
name     = "assimp"
category = "asset_loader"
assembly = "KernelEngine.Asset.Assimp"
native   = "ke_asset_assimp"

  [plugin.capabilities]
  formats = ["gltf", "glb", "fbx", "obj", "dae"]
```

**Conventions:**
- `category` is closed: `window`, `renderer`, `audio`, `input`, `asset_loader`, `task_scheduler`, `logger_sink`, `image_loader`, `image_decoder`, `dev_platform`.
- `capabilities` is free-form per category (renderer talks backends/features; window talks platforms).
- `option` lists project-level options the plugin reads from `Project.[runtime.<plugin>]` (chapter 16).

**Plugin manifests.** Each plugin folder ships a `plugin.toml` describing itself:

```toml
# src/csharp/KernelEngine.Render.Bgfx/plugin.toml
[plugin]
name = "bgfx"
category = "renderer"
assembly = "KernelEngine.Render.Bgfx"
native = "ke_render_bgfx"

[plugin.capabilities]
backends = ["vulkan", "d3d12", "metal", "opengl"]
features = ["pbr", "shadows", "post_fx", "compute"]
```

The build aggregates every `plugin.toml` it finds into one `plugin_database.toml`. Adding a new plugin = adding its manifest; no central registry to edit.

**Consumers:**
- Project scaffolder (`ke new project`): which plugins to wire by default.
- `ke add reference <plugin>` validates the name and updates `Project`.
- Editor GUI: shows available backends in a "renderer settings" UI.

## 5. `operation_database.toml`

Describes the Editor Lib operations themselves — what every CLI/GUI/agent can call.

```toml
[[operation]]
namespace = "Scene"
name      = "AddNode"
sync      = true
undoable  = true

  [[operation.arg]]
  name     = "parent"
  kind     = "NodeHandle"
  required = true

  [[operation.arg]]
  name     = "type"
  kind     = "string"
  required = true

  [[operation.arg]]
  name     = "name"
  kind     = "string"
  required = true

  [[operation.arg]]
  name     = "properties"
  kind     = "table<string, any>"
  required = false

  [operation.returns]
  kind = "Result<NodeHandle, EditorError>"

  [operation.errors]
  kinds = ["NotFound", "InvalidInput", "Conflict", "SchemaMismatch"]

[[operation]]
namespace = "Asset"
name      = "Import"
sync      = false
undoable  = false

  [[operation.arg]]
  name     = "sourcePath"
  kind     = "string"
  required = true

  [operation.returns]
  kind = "Task<Result<Unit, EditorError>>"

  [operation.errors]
  kinds = ["NotFound", "IOFailure", "Unsupported", "Cancelled"]
```

**Consumers:**
- CLI: builds verb/noun completion, validates arguments before dispatch, generates `ke help <op>`.
- Agent: `ke describe operations --json` returns this. First call against any project — the agent learns the entire surface in one shot.
- GUI editor: dispatches Ctrl+Z based on `undoable`, shows progress UIs on `sync = false` operations.

## 6. Generation pipeline

A single command produces all three:

```bash
ke build capabilities
```

Internally:
1. Reflect over loaded engine assemblies (or read source-gen output in AOT mode) → `class_database.toml`.
2. Walk `src/**/plugin.toml`, merge → `plugin_database.toml`.
3. Reflect over `KernelEngine.Editor.*` interfaces (or source-gen output) → `operation_database.toml`.

Triggers:
- Build target: regenerated whenever the relevant source changes.
- `ke add reference X` updates `plugin_database.toml` entry.
- `ke gen capabilities` for manual force.

Drift is impossible by construction: the databases are byproducts of the source, not curated independently.

## 7. Versioning

Each database carries a top-level `version` field. The Editor Lib accepts the version it was built against; older versions trigger a regen (`ke build capabilities`) with a warning; newer versions fail with "you have a stale `ke` binary, update it".

## 8. Why TOML and not JSON

JSON would be marginally more convenient for non-C# consumers (jq is everywhere). TOML wins because:

- These files are checked into the repo. Humans review the diff after a refactor moves properties around. TOML diffs read cleaner.
- The rest of the project's source-of-truth is already TOML; tooling that reads `Project` already has a TOML parser.
- Agents that prefer JSON are served by `ke describe ... --json` which streams the same content as JSON. **Storage format and interchange format are different concerns**; we don't need to constrain both.

## 9. What this is NOT

- **Not runtime configuration.** That's chapter 16. Capability databases describe *what the engine can do*; configuration describes *how the project is wired*.
- **Not a registry the user edits.** Hand-editing `class_database.toml` is wrong. Regenerate it.
- **Not a substitute for the C# type system.** Inside the engine, types are types. The DB exists for external consumers.

## 10. Cross-references

- The class part: [17 - Scene & Node Serialization §4](17%20-%20Scene%20%26%20Node%20Serialization.md#4-the-class-database--schema-as-data-not-code).
- The operation part: [18 - Editor Lib API](18%20-%20Editor%20Lib%20API.md).
- The CLI consumer: [19 - CLI & Agent Surface](19%20-%20CLI%20%26%20Agent%20Surface.md).
- Plugin philosophy this enables: [04 - C++ Plugins](04%20-%20C%2B%2B%20Plugins.md), [13 - Extensibility & Universality](13%20-%20Extensibility%20%26%20Universality.md).
