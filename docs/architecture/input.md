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
| action map | `ke_input_actions`, `InputActionMap` | framework | an `IInputReader` that is also an `INativeInputReader` | polled action values |
| system | none; the `Scene.Input` system of `SceneNodesModule` | framework | `IInput`, the action evaluator | the snapshot kept for the tick |

**The window feeds the sinks.** `ke_window_glfw_params` carries a borrowed, nullable `ke_input`.
While the window polls, each key, button, cursor and scroll event becomes a call to `on_key`,
`on_mouse_button`, `on_mouse_move` or `on_mouse_scroll`. With no input every event is dropped.
The managed `AddGlfwWindow` fills the field from `INativeInput` when the window singleton is first
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
"Scene.Input" runs in `KE_PHASE_PRE_UPDATE`, pinned to worker 1, with an empty access list: it
calls `Update` on `IInput`, captures a snapshot with `CaptureSnapshot`, keeps it in a field of
`SceneNodesModule`, and calls `Evaluate` on the action evaluator with it. Systems of later phases
read that field through `View`, so every read in the rest of the tick sees one snapshot.

**Actions are derived, not read from the edges.** The action layer reads only the `keys_down` and
`mouse_buttons_down` bitsets of the snapshot and derives its own edges by comparing one `evaluate`
with the previous one. `InputActionMap.Evaluate` passes no event callback, so managed code polls
action values and receives no `ke_input_action_event`.

## What the parts agree on without a contract

- The key and button codes are passed unchanged from the GLFW callbacks to `ke_input`; no table
  translates them.
- `KE_INPUT_MAX_KEYS` (512) and `KE_INPUT_MAX_MOUSE_BUTTONS` (32) bound the codes both sides send;
  a code outside them is ignored. The capacity of the event queue is private to the plugin.
- The system name "Scene.Input" and its worker, 1, are literals in `SceneNodesModule`.
- The window reads "runtime.window" in the configuration: "width", "height", "title",
  "fullscreen".
