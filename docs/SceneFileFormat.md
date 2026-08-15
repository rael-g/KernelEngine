# The scene file

> This is a **format reference**, not a design note: it describes rules a scene file
> has to follow to load. Where a rule is enforced, the enforcing code is cited — read
> that, not this, when the two disagree.

A scene is TOML. The extension is `.scene.toml`: `.scene` is the identity, `.toml` is
what lets any editor validate and colour it without a plugin.

```toml
[scene]
name    = "Main"
version = 2

[[entity]]
name = "Camera"
type = "camera"
[entity.transform]
position = [0.0, 0.0, 10.0]
[entity.camera]
orthographic      = true
orthographic_size = 5.0
```

## One shape for data: `[entity.<component>]`

Everything an entity carries is a component, addressed by the name it is registered
under. There is no property bag and no nesting under `components` — both were retired,
and a file still using them is refused rather than half-read.

Four keys are not components, because they describe how the graph is assembled rather
than what the entity is:

| key | meaning |
|---|---|
| `name` | what the entity is called, and what `parent` and `[[entity.connect]]` resolve against |
| `parent` | the entity to attach under, by name, within this file |
| `type` | the node type to instantiate onto the entity |
| `scene` | splice another scene file in at this point |

## Casing: one convention, everywhere

**Everything in a scene file is snake_case.** Component names, field names and node
type names alike. The C header declares the canonical spelling, and each language
binding applies its own casing on top:

| in the header | in the file | in C# |
|---|---|---|
| `ke_collider2d_component` | `[entity.collider2d]` | `Collider2D` |
| `half_extents` | `half_extents = [0.15, 0.9]` | `HalfExtents` |
| `Pong.Ball` (the C# type) | `type = "pong.ball"` | `Pong.Ball` |

A node type's name is normalized on the way in, so `Pong.Ball`, `pong.ball` and
`Pong.ball` are one name and the file can settle on the readable one — see
`NodeTypeRegistry.Normalize`. A digit does not split a word: `Sprite2D` is `sprite2d`,
never `sprite2_d`.

## Naming rules for a component

1. **A component is its struct name without prefix or suffix, in snake_case.**
   `ke_collider2d_component` → `collider2d`. Engine and game alike.
2. **A node's own component takes the node's name.** `Paddle` → `paddle`.
3. **Diverging is allowed and says something.** A struct with a name of its own means
   the data exists beyond the node: `transform` belongs to the spatial vocabulary,
   is written by physics and read by the hierarchy, and is not `Node3D`'s property.
4. **The short name is a shortcut while it is unique; the qualified one always works.**
   Two types claiming the same qualified name fail at registration. Two answering to
   the same short name fail when a scene writes the short one, naming both candidates.
   Adding a library therefore never changes what an existing scene means.

A qualified name in a table header needs quotes, because a dot is TOML's table
separator:

```toml
type = "sports.soccer.ball"
[entity."sports.soccer.ball"]   # always valid
[entity.ball]                   # shortcut, while only one ball is registered
```

## Rotation is authored in degrees

Stored in radians — as a quaternion in `transform`, as an angle in `transform2d` — and
written in degrees, because a file is read by people. `[entity.transform]` takes
`rotation_euler = [x, y, z]`; `[entity.transform2d]` takes `rotation = 90.0`.

## What fails the load

Loading a scene is synchronous, so a scene the engine cannot honour raises rather than
logging and continuing. A component nobody registered, a field the component does not
have, a retired block shape, a component the scene tree owns, an unresolvable parent,
and a signal connection that resolves to nothing all stop the load.

The field check is why every apply path marks what it took (`consumed` on
`ke_variant_table_entry`): a key claimed by neither the generated field table nor the
domain's own callback is a typo, and reporting it is the difference between a wrong
value and a value that quietly never arrives.

## Where the vocabulary comes from

Nothing in this file is hand-maintained per language. A component becomes authorable
the moment a C header describes it: kabic generates the `ke_component_field` table
from the header, and the framework's generic apply walks that table. `scripts/api_domains.json`
lists the described domains; `scripts/check_api_drift.cs` fails when a header and its
generated output disagree.
