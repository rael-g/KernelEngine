# Input

This is a map: the parts between the OS and a node, what each receives and what it hands on. How a
part works inside is on the generated page of its file. Contracts are under `src/c/input/` and
`src/c/window/`, plugins under `src/zig/input/` and `src/zig/window/`.

## The parts

| part | contract | plugin | receives | hands on |
|---|---|---|---|---|
| window | `ke_window` | glfw | OS events, a borrowed `ke_input` | calls on the four sinks of `ke_input` |
| input | `ke_input` | default | the sink calls | live queries, a `ke_input_snapshot`, a queue of events |
| managed input | `IInput`, `IInputReader` | `Input` in `KernelEngine.Input` | the native `ke_input` | an `IInputReader` over one snapshot |
| action maps | `ke_input_actions`, `InputActions` | framework | maps and actions added through its slots, from code or from the `input` section of a configuration; one snapshot per frame | polled action values |
| node field | `ke_action_ref` | framework | an action name, written by a scene or by code | the action's value through `axis` and `pressed` of `ke_node_ctx` |
| system | the "input.actions" system `ke_input_actions_create` registers when given a runtime | framework | the `ke_input` it was given | the actions evaluated for the tick |

**The window feeds the sinks.** `ke_window_glfw_create` takes a borrowed, nullable `ke_input`.
While the window polls, each key, button, cursor and scroll event becomes a call to `on_key`,
`on_mouse_button`, `on_mouse_move` or `on_mouse_scroll`. With no input every event is dropped.
The managed `AddGlfwWindow` passes `INativeInput` when the window singleton is first
resolved, so it is seen only if `INativeInput` is registered by then.

**An edge belongs to a frame.** `pressed` and `released` are set by the sink call that causes them
and cleared by the next `update` of `ke_input`; the queries and `get_snapshot` only read. Held
state (`down`, the cursor position) survives `update`. The queue of events is cleared by `update`
and by `drain_events`.

**A snapshot is a copy.** `get_snapshot` fills a `ke_input_snapshot` that holds no pointer back to
the input, so it can be read on any thread while the live object keeps changing. The live input
takes no lock: sinks, `update` and `get_snapshot` must not overlap.

## One tick

The host calls `PollEvents` on the window, then `Tick` on the runtime. The window module registers
no system, so the sink calls of a poll never interleave with a tick. Inside the tick, the system
"input.actions" runs exclusive in `KE_PHASE_PRE_UPDATE`: it calls `update` on the `ke_input`,
takes a snapshot with `get_snapshot` and evaluates the maps against it. Systems of later phases read actions, never keys, so every read in the rest
of the tick sees the values of one evaluation.

**Actions are derived, not read from the edges.** The action layer reads only the `keys_down` and
`mouse_buttons_down` bitsets of the snapshot and derives its own edges by comparing one `evaluate`
with the previous one. Code polls action values; no event is delivered.

**Maps decide who hears a key.** `evaluate` walks the enabled maps from the highest priority down,
and a key or mouse button bound in one is masked out of the snapshot the maps after it read. A
disabled map's actions are inactive and mask nothing.

**A configuration is a list of calls.** `ke_input_actions_create` walks the sections under
`input.map` of the configuration it is given and adds each map, action and binding through the same
slots a program calls; with no configuration the maps are whatever the program adds.

## What the parts agree on without a contract

- The key and button codes are passed unchanged from the GLFW callbacks to `ke_input`; no table
  translates them.
- `KE_INPUT_MAX_KEYS` (512) and `KE_INPUT_MAX_MOUSE_BUTTONS` (32) bound the codes both sides send;
  a code outside them is ignored. The capacity of the event queue is private to the plugin.
- The system name "input.actions" is a literal of `src/zig/framework/src/input_actions.zig`.
- The window reads "runtime.window" in the configuration: "width", "height", "title",
  "fullscreen".
