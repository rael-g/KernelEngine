# What does a scene file say, and what does the loader do with it?

A scene file is TOML, conventionally named `<name>.scene.toml` (`examples/csharp/games/pong/scenes/`),
parsed with tomlc99 (`toml_parse_file`, `src/zig/framework/src/scene_loader.zig:611`) and loaded by
`ke_scene_loader.load` (`scene_loader.h:31`). The rules below are the ones `scene_loader.zig` enforces.

What the loader **fails** on: a component block naming a component no module registered, a block key no
field or callback consumed, a retired or mis-written block, and a bad `parent`, `target` or `signal`.

What it **ignores without a word**: any top-level table other than the `[[entity]]` array (Pong's
`[scene] name = …, version = 2` header is read by nothing), and any scalar key on an entity other than
`name`, `parent`, `scene` and `type`: only tables are treated as component blocks
(`scene_loader.zig:379-398`), so a misspelt `nmae = "x"` does not fail.

## Shape

The file is an array of `[[entity]]` tables. A file with no `[[entity]]` loads successfully and
creates nothing (`scene_loader.zig:622-625`). Entities are created in file order.

```toml
[[entity]]
name = "Player"

[entity.transform]
position = [0.0, 1.0, 0.0]

[[entity.connect]]
signal = "hit"
target = "Hud"
```

## Keys on an entity

| key | meaning |
|---|---|
| `name` | Required, unless the entity is the root of an included scene whose includer supplies one (`scene_loader.zig:518`). |
| `parent` | The `name` of an entity **declared earlier in the same file**; otherwise `not_found` (`:570-577`). Without it the entity attaches to the scene tree's root. |
| `scene` | Path of another scene file, instantiated in place of a node. See *Including a scene*. |
| `type` | A script type name, handed to the registered script factory once the entity's components are applied (`:246`, dispatch at the end of `processEntity`). |
| `[entity.<component>]` | A component block. See below. |
| `[[entity.connect]]` | A signal connection. See below. |

## Names

A scene file spells four kinds of name, and the loader treats them differently.

| written as | names | matched how |
|---|---|---|
| `[entity.<name>]` | a component | **as written**, against the names modules registered (`scene_loader.zig:310`) |
| a key inside a block | a field of that component | as written, against the field table (`component_fields_apply.zig:17-35`) |
| `type = "<name>"` | a node type | **normalized**, qualified name first, then short name |
| `signal = "<name>"` | a signal | as written, against the signals declared to the bus (`scene_loader.zig:446`) |
| `parent`, `target` | an entity of the same file | as written (`NameMap.get`, `:522-527`) |

**Component and field names are snake_case and spelled by the header.** A component's name is its
struct's name without the `ke_` prefix and the `_component` suffix, emitted beside the struct as a
`KE_COMPONENT_NAME_*` macro (`src/c/spatial/kernel_engine/spatial/component_fields.h:9-11`:
`transform`, `transform2d`, `world_transform`); a field's key is the field's name in the header. A
block name is not normalized and has no short form: `[entity.Transform2D]` is not `[entity.transform2d]`, and
`[entity.ball]` names a component called exactly `ball`. A game-authored node's own component is
named after its class in snake_case with the namespace dropped, and its property keys are the
properties in snake_case (`NodePropertyGenerator.cs:86`, `:426`;
[node-types.md](../architecture/node-types.md#names-a-scene-can-use-for-one-node-type)).

**A node type is normalized.** `+` becomes `.`, and an uppercase letter starts a new `_`-separated word
unless it follows `.`, `_`, a digit or another uppercase letter that is not the start of a lowercase run.
So `Pong.Ball`, `Pong+Ball` and `pong.ball` are one name, `Sprite2D` is `sprite2d`, `HTTPServer` is
`http_server`, and normalizing a normalized name changes nothing. The native loader normalizes the string
before it calls the script factory, so the factory receives the one spelling
(`normalizeTypeName`, `scene_loader.zig:194-229`; tests `:1898-1932`); the managed registry normalizes
the names it registers with the same rule. What the normalized name is looked up in, and what a short
name may collide with, is in [node-types.md](../architecture/node-types.md#resolving-a-node-type).
A scene that names a type nobody registered, or a short name two types answer to, fails the load with
the registry's message (the managed factory's exception reaches the loader as its failure,
`Generated/SceneLoader.g.cs:135-152`).

**A type and a block are separate namespaces.** `type = "pong.paddle"` resolves a node type;
`[entity.paddle]` is the component that node declares. Neither implies the other: a block without a `type`
gives an entity that carries the component and no managed node, and a `type` without the block binds the
node over the component's defaults. When both are present the block is applied first and the factory
runs after it, so a node binds onto the values the scene authored
(`processEntity`, `scene_loader.zig:571`, `:615`; `Node.GeneratedSeed`, `Node.cs:208-212`).

## Component blocks

A table named `[entity.<name>]` is a component block, `<name>` being the name a module registered
the component under. The loader looks it up in the ECS and fails if no module registered it
(`:332`). The component must also have a field table, an apply callback, or both registered in the
world (`:341`; [framework.md](../architecture/framework.md#the-world)).

For a component the entity does not yet have, the loader zeroes it and seeds the defaults the field
table declares (`:350-354`). It then applies the block's keys through the field table, then through
the apply callback for whatever a table cannot describe (`:363-374`).

**Every key in the block must be taken by one of the two.** A key neither consumed is an error:
`component '<name>' has no field '<key>'` (`:377`). A typo cannot pass silently.

Three blocks are refused by name:

- `[entity.components]` and `[entity.properties]` are retired; the error says to write
  `[entity.<component>]` directly (`:391-397`).
- `[entity.connect]` in the singular is refused, since a connection is `[[entity.connect]]` (`:386`,
  `:421`).
- The two components the scene tree owns, name and hierarchy, cannot be authored (`:399-404`).

Values read from TOML become variants: string, integer, float, boolean, an array of numbers or a nested
table (`scene_loader.zig:91-145`). An array of two, three or four-or-more numbers becomes a vector of 2, 3 or
4 components (elements past the fourth are dropped); an array of any other length reads as null (`:96-117`).

## Values

A block key is applied in up to three ways, and they do not fail alike.

1. **The generated field table.** The key is matched to a field and the value written by the field's
   type (`component_fields_apply.zig:17-35`). A value the field cannot take writes nothing, and the key
   is **claimed** all the same, so no "no field" error follows.
2. **An apply callback**, for what a table cannot describe. It claims the keys it owns
   (`keyIs`, `components_apply.zig:15-21`), and a value outside its domain fails the load with the
   callback's own message.
3. **A callback that returns false without an error** fails the load with
   `component '<name>' was given a value it cannot hold` (`scene_loader.zig:342-351`).

A callback may be written in managed code: a game node's apply reads each supported property by
its key and **ignores** a value of the wrong type or an enum name that does not parse
([node-types.md](../architecture/node-types.md#what-binding-a-typed-entity-does)).

The callbacks the engine ships:

| component | key | domain | stored as |
|---|---|---|---|
| `transform` | `rotation_euler` | three numbers, **degrees** | the quaternion `rotation` (`components_apply.zig:64-85`) |
| `transform` | `scale` as `[x, y]` | two numbers | `scale.z` is set to `1` (`components_apply.zig:80-82`) |
| `transform2d` | `rotation` | a number, **degrees** | radians (`components_apply.zig:45-63`) |
| `camera` | `fov_degrees` | a number strictly between 0 and 180 | `fov`, multiplied by pi/180 (`src/zig/render/module/src/component_apply.zig:28-50`) |
| `mesh`, `sprite2d` | `alpha_mode` | the string `'opaque'`, `'mask'` or `'blend'` | the enumerator (`component_apply.zig:51-92`) |

Outside its domain, each of the rotation, field-of-view and alpha keys fails the load: a
`rotation_euler` that is not three numbers, a `rotation` that is not a number, an `alpha_mode` that is
not one of the three strings (an integer included), a `fov_degrees` of `0` or `180`.

## Connections

`[[entity.connect]]` wires a signal this entity emits to another entity. `signal` and `target` are
both required; `handler` is an optional integer, `0` when absent (`:440-485`).

- `target` is the `name` of an entity in the same file, in **any** position: connections are resolved
  in a second pass after every entity exists (`:700-708`).
- `signal` must be one a node type declared to the signal bus (`signal_lookup`); an unknown name
  fails the load, and the name is matched as written, which for a managed node is the payload
  struct's own name ([framework.md](../architecture/framework.md#signals-are-declared-before-a-scene-loads)).
- **A connection reaches only inside its own file.** The name table is per file: each call of
  `loadSceneRecursive` makes its own and frees it on return (`scene_loader.zig:627`). An included scene
  publishes one name to the file that includes it, the including entity's `name`, bound to the included
  scene's root (`:597`). A `target` in the including file therefore cannot name an entity inside the
  subscene other than its root, and a connection inside the subscene cannot name an entity of the
  including file; either fails the load with `connect targets '<name>', which this scene declares no
  entity for` (`:470-473`).
- A `[[entity.connect]]` written on the **including** entity (the one with `scene =`) has the included
  root as its source, and its target is resolved in the including file (`:700-708`).
- A scene that declares a connection while the world has no signal bus fails the load.

## Including a scene

`scene = "<path>"` loads another scene file and attaches its first entity at this point, under the
entity's `parent` (or the root). The included file's first entity takes this entity's `name`, and this
entity's own component blocks and `type` are applied on top of it (`:580-625`).

A path beginning with `res://` is the project root joined with the rest. A path starting with `/` or
a drive letter is used as written. Any other path is relative to the directory of the file that names
it (`scene_loader.zig:173-190`).

## Failure

The first failure ends the load and returns `false`. Entities already created for that file stay in
the tree: the loader does not remove them (`loadSceneRecursive`, `scene_loader.zig:601-673`).
