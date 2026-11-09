# Input section

Input actions are written in the `input` section of the Project file (`project-file.md`).
`ke_input_actions_create`, given a configuration and the section, walks `input.map` and adds each
map, action and binding through the same slots a program calls. How the bindings are evaluated
each tick is in `architecture/input.md`.

## Shape

```toml
[input.map.Pong]
priority = 0

[input.map.Pong.action.PaddleLeftMove]
type = "Axis1D"
bindings = [{ kind = "key_pair", negative = "S", positive = "W" }]

[input.map.Pong.action.Launch]
bindings = [{ kind = "key", key = "Space" }]
```

| table | keys |
|---|---|
| `input.map.<map>` | `priority` (an integer, 0 when absent; higher maps are evaluated first), `enabled` (true when absent) |
| `input.map.<map>.action.<action>` | `type`: `Button` (when absent), `Axis1D`, `Axis2D` or `Axis3D`; `bindings`: an array of tables |
| a binding | `kind`, and the keys that kind needs |

| `kind` | keys |
|---|---|
| `key` | `key` |
| `key_pair` | `negative`, `positive` |
| `key_quad` | `up`, `down`, `left`, `right` |
| `mouse` | `button` |

A key is written by its name in the key table of `input_actions.zig` (`Space`, `W`, `Up`,
`Escape`), a mouse button by its name (`Left`).

## What fails

Creating the input actions fails, with the reason logged naming the section, on an unknown action
type, a binding without `kind` or of an unknown kind, a binding missing a key its kind needs, and a
key or mouse button name not in its table.
