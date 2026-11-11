# Scene file

A scene file is TOML, named `<name>.scene.toml` by convention (`examples/csharp/games/pong/scenes/`).
`ke_scene_files.instantiate` reads it and spawns its nodes through `ke_node_types`, as a program
calling `spawn` would; `ke_scene_files.open` puts the first one in a scene slot, and a node
changes it with `ctx->change_scene`. The rules below are the ones `scene_files.zig` enforces.

## Shape

The file is an array of `[[entity]]` tables, spawned in file order; a file with none spawns
nothing. An optional `[scene]` table holds `version`, which must be 2.

```toml
[[entity]]
name = "Ball"
type = "pong.ball"

[entity.transform2d]
position = [0.0, 0.0]

[entity.ball]
initial_speed = 6.0
```

## Keys on an entity

| key | meaning |
|---|---|
| `name` | Required, unless the entry is the first of a scene another entry references, which takes the referencing entry's name. |
| `parent` | The `name` of one entry declared earlier in the same file; without it the node goes under the parent the file is instantiated under. |
| `type` | The node type, as registered (`pong.ball`, `label`); without it the base type `node`. |
| `scene` | Another scene file, instantiated in place of a node; its first entry takes this entry's name, parent and blocks. An entry names a scene or a type, never both. |
| `[entity.<component>]` | A block of values written over what a node of the type is born with. |

## Blocks and values

A block names a component the node's type carries, by its registered name (`transform2d`, `sound`),
or by the name inside the type's namespace (`[entity.ball]` for the fields of `pong.ball`). Each key
names a field of the component's field table and is written through the ecs's
`component_field_write`, which converts the value to the field's type:

| TOML | written as |
|---|---|
| boolean, integer, float, string | the same kind; an integer and a float convert to each other |
| an array of 2, 3 or 4 numbers | a vector of that width |
| a string for a field with enum names | the index of the name (`release = "when_done"`) |

## What fails

The load fails, with the reason logged, on: a top-level key other than `entity` and `scene`; a
`[scene]` key other than `version`, or another version; an entry key that is not one of the keys
above; a block the type does not carry, a component with no field table, a key no field has, or a
value the field cannot hold; an entry without a name; a `parent` no earlier entry has, or one two
entries share; an entry naming both a scene and a type; a type never registered; a missing file or
one that does not parse. `[[entity.connect]]` is refused: a node raises an event instead.

A `res://` path is resolved by the asset resolver against the project root; an absolute path is read
as written, and any other against the directory of the file that names it.
