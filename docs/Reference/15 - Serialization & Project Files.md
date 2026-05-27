# 15 — Serialization & Project Files

> **Status**: 📋 Specification. No serialization is implemented yet; this chapter freezes the format choices and file schemas so implementation across the editor lib, runtime loader, and CLI tooling shares the same contract.

## 1. Format choice: TOML for human files, binary for the rest

**Human-facing files use [TOML](https://toml.io).** That means project files, scene files, resource manifests, settings — anything a developer might open in a text editor, diff in git, or merge by hand.

Why TOML over the alternatives:

- **YAML** — significant whitespace and implicit type coercion (the "Norway problem", `no` → `false`) make merges error-prone and tooling brittle. Unity uses YAML and regrets it publicly. **Rejected.**
- **JSON** — no comments, awkward for hand-editing, no native section grouping. Fine for machine output, hostile to humans. **Used only for machine traces (logs, headless replay output).**
- **INI** — flat, no real type system, no nesting beyond sections. **Rejected.**
- **Custom format** — Godot's `.tscn` proves this can work, but every custom parser is a maintenance liability. **Rejected.**
- **TOML** — explicit types, comment support, clear section semantics (`[table]`, `[[array_of_tables]]`), good tooling in every language, hard to merge wrong. **Chosen.**

**Binary formats keep the data they were born as.** Meshes, textures, audio, compiled shaders — these stay in their native binary forms (glTF, KTX2, PNG/JPG, SPIR-V). A `.toml` resource manifest may *describe* a binary asset, but never inlines it.

### 1.1 Machine output is JSON Lines, not TOML

Headless replay traces, structured logs, agent introspection responses — these are JSONL. They are produced and consumed by machines, never edited by hand, and JSONL is the lingua franca for streaming records.

> TOML for the source of truth. JSONL for the observation stream.

## 2. File catalog

| File | Format | Purpose | Versioned in git |
|---|---|---|---|
| `Project` | TOML | Root project manifest. One per project. | ✅ |
| `User.local` | TOML | Per-developer overrides (window pos, last opened scene). | ❌ (gitignored) |
| `scenes/*.scene` | TOML | Serialized scene (node tree + resource refs). | ✅ |
| `resources/**/*.material` | TOML | Material definitions. | ✅ |
| `resources/**/*.skybox` | TOML | Skybox / cubemap definitions. | ✅ |
| `assets/**/*` | native binary | Meshes, textures, audio. | ✅ (or LFS) |
| `assets/**/*.import` | TOML | Import settings for a binary asset (compression, mipmaps, etc.). | ✅ |
| `bin/`, `obj/`, `build/` | — | Build artifacts. | ❌ |

A project is a folder containing `Project` at the root. Everything else is referenced from there.

## 3. Asset reference scheme

All cross-file references use the `res://` URI scheme, paths relative to the project root.

```toml
mesh     = "res://assets/meshes/cube.glb"
material = "res://resources/materials/red.material"
texture  = "res://assets/textures/wall.png"
```

Rules:
- Forward slashes only, regardless of host OS.
- Case-sensitive (avoids "works on Windows, breaks on Linux").
- A reference is invalid if the target file does not exist; the loader fails loudly with the offending path and the file that contained the reference.
- No GUIDs, no `.meta` sidecars. Path *is* the identity. If files are renamed, references break — that is a feature (it is also `git mv`-able with grep). Editors offer a "rename + update refs" operation.

GUIDs may revisit later if collaborative editing demands them. For now, simple path-based references are cheaper and easier to reason about.

## 4. `Project` schema

The project manifest. Analogous in role to `Cargo.toml` or Godot's `project.godot`. Single file, project root.

```toml
[project]
name        = "MyGame"
version     = "0.1.0"
description = "A first KernelEngine project."
default_scene = "res://scenes/Main.scene"

[runtime]
# Plugins selected by name; the lib resolves them via DI registration.
window   = "glfw"          # KernelEngine.Window.Glfw
renderer = "bgfx"          # KernelEngine.Render.Bgfx
input    = true            # AddInput()
logging.sinks = ["console"]

[runtime.window]
width      = 1280
height     = 720
title      = "MyGame"
fullscreen = false
vsync      = true

[runtime.renderer]
shader_path = "shaders"    # relative to AppContext.BaseDirectory
backend_hint = "vulkan"    # passed to backend if it supports the hint

[determinism]
# Read by --headless / replay flows; ignored by regular runs unless
# `force = true` is set. See chapter 14, §5.1.
seed             = 0
fixed_timestep   = 0.01667 # 60 Hz simulated, regardless of wall clock
force            = false

[build]
# `ke build` consumes these; the runtime ignores them.
targets = ["win-x64", "linux-x64"]
output  = "build/dist"

[dependencies]
# Future: external packages (asset packs, third-party plugins).
# Empty / absent for now.
```

### Reserved top-level sections

`[project]`, `[runtime]`, `[determinism]`, `[build]`, `[dependencies]`, `[editor]`. Everything else under a top-level key the engine does not recognize is **preserved on write** and ignored on read — game-specific config can live in `[game]` or any namespaced table without the engine touching it.

## 5. Scene file schema (`*.scene`)

A scene is a tree of nodes, each with a name, a type, an optional parent reference, and a per-type property bag. The format mirrors the runtime `Tree` exactly — load is a straight tree-build, save is a pre-order walk.

```toml
[scene]
name = "Main"
# Optional version stamp — the loader rejects future major versions
# and migrates between minor versions if a migrator is registered.
version = 1

# Each node is an entry in [[node]]. Order matters: a child's `parent`
# must appear earlier in the array. The root is implicit — first node
# with no `parent` becomes a child of the tree root.

[[node]]
name = "Camera"
type = "Camera"
transform = { position = [0, 5, 10] }
properties = { Fov = 60, Near = 0.1, Far = 1000 }

[[node]]
name = "Sun"
type = "DirectionalLight"
properties = { Direction = [0.5, 1, 0.5], Color = [1, 1, 1], Intensity = 10 }

[[node]]
name = "Floor"
type = "MeshRenderer"
transform = { scale = [10, 1, 10] }
properties = { Mesh = "res://assets/meshes/plane.glb",
               Material = "res://resources/materials/grey.material" }

[[node]]
name = "Cube"
type = "MeshRenderer"
parent = "Floor"                      # Cube becomes a child of Floor
transform = { position = [0, 1, 0] }
properties = { Mesh = "res://assets/meshes/cube.glb",
               Material = "res://resources/materials/red.material" }
```

### Field semantics

| Key | Required | Notes |
|---|---|---|
| `name` | ✅ | Unique within the scene; the engine appends a suffix if not. |
| `type` | ✅ | Fully qualified or short name of a registered Node type (`Camera`, `MeshRenderer`, `MyGame.PlayerNode`). Loader fails on unknown types. |
| `parent` | optional | Name of an earlier node in this scene. Omitted = direct child of root. |
| `transform.position` / `.rotation` / `.scale` | optional | Defaults: zero / identity quaternion / one. Rotation accepts `[x,y,z,w]` quaternion or `{euler = [x,y,z]}` in degrees. |
| `properties` | optional | Type-specific. Engine resolves to settable public properties on the node class via reflection (init or set). Unknown keys are a load error unless `[scene] strict = false`. |

### Reusable scenes (the `Scene` bundle)

A scene can include another scene as a subtree:

```toml
[[node]]
name = "EnemySpawn"
include = "res://scenes/EnemyTemplate.scene"
transform = { position = [10, 0, 0] }
```

`include` is mutually exclusive with `type`. The included scene's root becomes the named node here, and its tree is grafted in place. This implements the `Scene` reusable-bundle concept from the Tier 2 refactor — disk-side equivalent of `scene.Instantiate(tree, parent)`.

## 6. Resource files

Resources that have meaningful authored data (materials, skyboxes, terrain layers) get TOML manifests. Resources that are pure binary (meshes, textures) stay binary with optional `.import` sidecars.

### 6.1 Material (`*.material`)

```toml
[material]
name = "Red"
shader = "pbr"                 # built-in shader name

base_color = [0.8, 0.2, 0.2, 1.0]
metallic   = 0.0
roughness  = 0.5

[textures]
albedo = "res://assets/textures/brick_albedo.png"
normal = "res://assets/textures/brick_normal.png"
# Absent textures → engine defaults (white for albedo, flat normal, etc.).
```

**Inline alternative inside a scene.** For one-off materials used by a single node, skip the
file and define the material as an inline table on the node's `Material` property:

```toml
[[node]]
name = "Floor"
type = "MeshRenderer"
properties.Mesh = "res://primitives/plane"
properties.Material = { base_color = [0.5, 0.5, 0.5, 1.0], metallic = 0.0, roughness = 0.8 }
```

The inline table accepts the same keys as the file's `[material]` section. Use files when the
same material is shared across multiple scenes; use inline when a node needs a unique surface
that no other node references.

### 6.2 Skybox (`*.skybox`)

```toml
[skybox]
name = "DesertNoon"
cubemap = "res://assets/cubemaps/desert.ktx2"
ibl = true                     # generate diffuse + specular IBL maps
```

### 6.3 Asset import settings (`*.import`)

A sidecar next to a binary asset, optional. Without it, the loader uses defaults.

```toml
# Lives at: assets/textures/wall.png.import
[import]
type       = "texture"
srgb       = true
mipmaps    = true
compression = "bc7"            # bc7 / bc1 / none
```

```toml
# Lives at: assets/meshes/character.glb.import
[import]
type            = "mesh"
generate_normals = false       # use what's in the file
scale_factor     = 1.0
```

The loader reads `<asset>.import` if it exists, falls back to format defaults otherwise.

## 7. `User.local` (gitignored)

Per-developer state that should never be committed. The editor / CLI writes here freely; the runtime ignores it.

```toml
[editor]
last_opened_scene = "res://scenes/Level3.scene"
window.position = [120, 80]
window.size     = [1600, 900]

[runtime.overrides]
# Local overrides for Project.[runtime] — useful for "I want a smaller
# window while debugging" without polluting the committed project file.
window.width  = 800
window.height = 600
```

Reading precedence: `Project` is the base; `User.local.[runtime.overrides]` shallow-merges on top.

## 8. Versioning & migration

Every TOML file the engine writes carries an integer `version` in its primary table (`[project]`, `[scene]`, `[material]`, etc.). On load:

- **Same version** → load normally.
- **Older version** → run the registered migrator chain, then load. Migrators are pure transformations between adjacent versions; the engine logs which ran.
- **Newer version** → fail with a clear message. No silent downgrades.

Bumps are infrequent and accompanied by a migrator. The schema for `version 1` is what is documented in this chapter; future bumps will be appended here, not rewritten in place.

## 9. Implementation notes (when the work begins)

- C# parser: [Tomlyn](https://github.com/xoofx/Tomlyn). Mature, MIT, zero-alloc readers available.
- All file IO routes through `KernelEngine.Editor` — the runtime engine does not parse TOML directly; it consumes already-parsed in-memory models. This keeps Tomlyn out of the runtime hot path and lets the runtime be statically AOT-compatible later.
- Write paths emit canonical TOML (sorted keys within a table, two-space indent, no trailing whitespace) so git diffs are minimal.
- Schemas are checked into `docs/Schemas/` as TOML examples with comments — those examples are loaded by tests to keep documentation and code aligned.

## 10. What is intentionally not specified

- **Binary format for compiled scenes.** A future "build" step may compile `*.scene` into a `.scene.bin` for shipping (faster load, no parser at runtime). Deferred until profiling shows TOML load time matters.
- **Network sync of scenes.** Multiplayer / collaborative editing implies a delta protocol on top of these files. Not in scope yet.
- **Nested arrays of nodes.** TOML supports `[[node.child]]` etc., but using flat `parent = "..."` references is simpler to author and to merge. Revisit if scene files get unwieldy.

## 11. Cross-references

- The editor surface that reads and writes these files: [14 - Editor, CLI & Agent Layer](14%20-%20Editor%2C%20CLI%20%26%20Agent%20Layer.md).
- The runtime Tree the scene files mirror: [06 - Framework](06%20-%20Framework.md).
- Asset loaders that consume `.import` sidecars: [09 - Assets & Pipelines](09%20-%20Assets%20%26%20Pipelines.md).
