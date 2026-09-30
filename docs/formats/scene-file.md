# What does a scene file say, and what does the loader do with it?

A scene file is TOML, conventionally named `<name>.scene.toml` (`examples/csharp/games/pong/scenes/`),
parsed with tomlc99 (`toml_parse_file`, `src/zig/framework/src/scene_loader.zig:648`) and loaded by
`ke_scene_loader.load` (`scene_loader.h:31`). The rules below are the ones `scene_loader.zig` enforces.

What the loader **fails** on: a component block naming a component no module registered, a block key no
field or callback consumed, a retired or mis-written block, and a bad `parent`, `target` or `signal`.

What it **ignores without a word**: any top-level table other than the `[[entity]]` array (Pong's
`[scene] name = …, version = 2` header is read by nothing), and any scalar key on an entity other than
`name`, `parent`, `scene` and `type`: only tables are treated as component blocks
(`scene_loader.zig:406-425`), so a misspelt `nmae = "x"` does not fail.

## Shape

The file is an array of `[[entity]]` tables. A file with no `[[entity]]` loads successfully and
creates nothing (`scene_loader.zig:659-662`). Entities are created in file order.

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
| `name` | Required, unless the entity is the root of an included scene whose includer supplies one (`scene_loader.zig:555`). |
| `parent` | The `name` of an entity **declared earlier in the same file**; otherwise `not_found` (`:570-577`). Without it the entity attaches to the scene tree's root. |
| `scene` | Path of another scene file, instantiated in place of a node. See *Including a scene*. |
| `type` | A script type name, handed to the registered script factory once the entity's components are applied (`:246`, dispatch at the end of `processEntity`). |
| `[entity.<component>]` | A component block. See below. |
| `[[entity.connect]]` | A signal connection. See below. |

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

Values read from TOML become variants: string, integer, float, boolean, an array of numbers (a
vector) or a nested table (`scene_loader.zig:96-153`).

## Connections

`[[entity.connect]]` wires a signal this entity emits to another entity. `signal` and `target` are
both required; `handler` is an optional integer, `0` when absent (`:440-485`).

- `target` is the `name` of an entity in the same file, in **any** position: connections are resolved
  in a second pass after every entity exists (`:700-708`).
- `signal` must be one a node type declared to the signal bus (`signal_lookup`); an unknown name
  fails the load.
- A scene that declares a connection while the world has no signal bus fails the load.

## Including a scene

`scene = "<path>"` loads another scene file and attaches its first entity at this point, under the
entity's `parent` (or the root). The included file's first entity takes this entity's `name`, and this
entity's own component blocks and `type` are applied on top of it (`:580-625`).

A path beginning with `res://` is the project root joined with the rest. A path starting with `/` or
a drive letter is used as written. Any other path is relative to the directory of the file that names
it (`scene_loader.zig:183-200`).

## Failure

The first failure ends the load and returns `false`. Entities already created for that file stay in
the tree: the loader does not remove them (`loadSceneRecursive`, `scene_loader.zig:638-710`).
