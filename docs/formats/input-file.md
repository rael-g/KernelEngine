# What does an input file say, and what does the loader do with it?

An input file is TOML, conventionally named `actions.input` (`examples/csharp/games/pong/actions.input`),
parsed with tomlc99 by `ke_input_actions.load` (`vtLoad`, `src/zig/framework/src/input_actions.zig:330`).
It binds named actions to keys and mouse buttons. How the bindings are evaluated each tick is in
`architecture/input.md`.

What the loader **fails** on: a missing or unopenable file (`KE_ERROR_NOT_FOUND`), a file tomlc99
cannot parse (`KE_ERROR_IO`), and an allocation failure (`input_actions.zig:346-356`, `366-368`,
`387-390`).

What it **ignores without a word**: everything listed under "What is skipped" below. In particular a
misspelt key name does not fail; it binds a key that can never be down.

## Shape

```toml
[action.PaddleLeftMove]
type = "Axis1D"
bindings = [
    { kind = "key_pair", negative = "S", positive = "W" },
]

[action.Launch]
type = "Button"
bindings = [
    { kind = "key", key = "Space" },
]
```

Each table directly under `[action]` is one action, and its name is the table's name
(`input_actions.zig:359-364`). A file with no `[action]` table loads successfully and defines nothing
(`:359`). Anything else at the top level is read by nothing. Action names are stored in 64 bytes;
a longer name is truncated at 63 characters (`:9`, `231-235`).

Actions are numbered from 0 in the order tomlc99 enumerates them, which `get_action_id` reports by
name (`:363-396`, `402-406`; test `actions are numbered in the order the file declares them`,
`:781`). Managed code never sees the number: `InputActionMap<TEnum>.LoadFromFile` asks for each enum
value's name with `value.ToString()` and keeps the ids it finds
(`src/csharp/framework/KernelEngine.Framework/Input/InputActionMap.cs:27-39`).

`load` discards every action already in the instance before it opens the file, including ones added
by `add_action`, so a load that fails on a missing file leaves the instance empty (`:344-346`).

## `type`

`"Button"`, `"Axis1D"`, `"Axis2D"` or `"Axis3D"`. Any other string, and an absent `type`, is a Button
(`parseActionType`, `:112-119`; `:374-378`).

## `bindings`

An array of inline tables, each with a `kind`. A binding table that does not parse is skipped and the
rest of the array still loads (`:380-394`).

| `kind` | other keys | what it contributes |
|---|---|---|
| `"key"` | `key` | `x = 1` while the key is down |
| `"key_pair"` | `negative`, `positive` | `x = +1` for `positive`, `-1` for `negative`, `0` if both or neither |
| `"key_quad"` | `up`, `down`, `left`, `right` | `x = right - left`, `y = up - down` |
| `"mouse"` | `button` | `x = 1` while the button is down |

(`parseBindingTable`, `:278-328`; contribution, `sampleBinding`, `:255-271`.)

Key names are the exact, case-sensitive strings of `key_table`: `A`..`Z`, `Number0`..`Number9`,
`Keypad0`..`Keypad9`, `F1`..`F25`, `Space`, `Enter`, `Escape`, `Tab`, `Backspace`, `Up`, `Down`,
`Left`, `Right`, `ShiftLeft`, `ControlLeft`, and the rest of the table (`:22-84`). Mouse button names
are `Left`, `Right` and `Middle` (`:86-90`); buttons 4 to 8 of `ke_mouse_button` have no name.

## What is skipped

- A **key name or mouse button name that is not in its table** does not fail the binding. The lookup
  returns `KE_KEY_UNKNOWN` (-1) or `-1`, the binding is stored, and it reads as never down because
  every down-test rejects negative codes (`lookupKey`, `lookupMouseButton`, `:92-108`; `isKeyDown`,
  `isMouseDown`, `:237-246`).
- A binding table with an unknown `kind`, or missing a key it needs, is dropped (`:285-327`, `386`).
- An entry under `[action]` that is not a table is skipped (`:364`).
- An action with no `bindings` array loads and is never active.

## What an action evaluates to

Per action, per `evaluate`, over its bindings (`input_actions.zig:553-578`):

- A binding is *active* when its contribution is non-zero. The action is active when any binding is.
- A **Button** that is active reads `x = 1`.
- Any other type reads, per component, the contribution with the largest absolute value across its
  bindings. A `key_pair` contributes `x` only; a `key_quad` contributes `x` and `y`; `z` is never
  contributed by any binding kind.
- `is_action_down` is the active flag. `was_action_pressed` is active now and not at the previous
  `evaluate`; `was_action_released` is the reverse (`:618-633`). `get_axis1d` reads `x`
  (`:635-638`).
- With a callback, `evaluate` also emits STARTED when the action turns active, CANCELED when it
  turns inactive, and, for non-Button actions that stay active, PERFORMED when any component changed
  (`:580-605`).

An action id outside the loaded range reads inactive and zero, and `evaluate` with a null snapshot
fails with `KE_ERROR_INVALID_ARGUMENT` (`:541-544`, `:610-616`).

## Where the file is found

`AddInputActions<TEnum>(path)` loads in the singleton factory, so at the map's first resolution, from `path` resolved against
`AppContext.BaseDirectory`, or `actions.input` there when `path` is null
(`src/csharp/framework/KernelEngine.Framework/Input/InputActionsServiceCollectionExtensions.cs:17-21`).
An enum member with no `[action.<Name>]` table is not an error; its queries read false and zero
(`InputActionMap.cs:33-37`, `50-59`). The Project file's `[input] actions` key is read only by the
`ke` command-line tool (`formats/project-file.md`).
