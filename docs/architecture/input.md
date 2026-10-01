# How does a key press reach a system body, and when is its edge visible?

Four pieces carry it. The window plugin turns OS events into calls on `ke_input`'s sinks. The
`ke_input` plugin folds them into state. A managed system takes a frozen copy of that state once per
tick. A second system evaluates action bindings against the copy
(`formats/input-file.md`). Node code then reads either.

## The state: `ke_input`

`ke_input` is a vtable (`src/c/input/kernel_engine/input/input.h:16-130`); its one implementation is
`ke_input_default` (`src/zig/input/default/src/input_default.zig`). It holds per-key `down`,
`pressed` and `released` flags, mouse position, per-frame mouse and scroll deltas, three mouse-button
bitmasks, and a queue of discrete events (`input_default.zig:18-36`).

The four **sinks** are how the window backend writes state: `on_key`, `on_mouse_move`,
`on_mouse_button`, `on_mouse_scroll` (`input.h:102-128`).

- A key press sets `down`, and sets `pressed` only if the key was not already down
  (`input_default.zig:81-84`). A release sets `released` and clears `down` (`:84-87`). Key codes
  outside `0..KE_INPUT_MAX_KEYS` (512) are dropped (`:76`).
- Mouse motion adds the distance from the previous position to `mouse_dx/dy` and stores the new
  position (`:94-100`); scroll adds to `scroll_dx/dy`. Mouse buttons follow the key rule
  on a 32-bit mask.
- Every key and button transition and every scroll also appends to the event queue, up to 512
  entries; a full queue drops the event and sets a flag no header exposes (`:16`, `:43-53`,
  `grep -rn overflow src/c/input` prints nothing). Mouse motion appends a `KE_INPUT_EVENT_MOUSE_MOVE`
  too, but only once per poll: later moves overwrite the position of that one queued event
  (`:94-109`), so a burst of motion cannot fill the queue and starve key events.

`update` is the frame boundary: it clears every `pressed` and `released` flag, the mouse and scroll
deltas, the pressed and released button masks, and the event queue. It leaves `down`, the button
`down` mask and the cursor position (`input_default.zig:55-74`).

## What an edge is, and until when it lasts

An edge (`pressed`, `released`) is set by the sink call that causes it and cleared by the next
`update`. Nothing else clears it: `get_snapshot` and the `is_key_*` queries only read
(`input_default.zig:136-178`; test `a key press is visible until the next update`, `:298`). So an
edge is visible to every read made between the sink call that set it and the next `update`, and to
no read after. A press and release both landing between two `update` calls leave `pressed` and
`released` both set and `down` false.

## The snapshot

`get_snapshot` copies the state into a `ke_input_snapshot`: three 512-bit key bitsets, mouse
position, deltas, scroll, and the three button masks (`snapshot.h:14-52`,
`input_default.zig:154-178`). The copy is a plain struct with no pointer back, so it can be read on
any thread while the live object keeps changing (`input.h:44-49`). Reads go through the
`snapshot_is_*` slots of `ke_input`, which treat out-of-range codes as false
(`input.h:51-91`, `input_default.zig:180-228`).

`ke_input_default` takes no lock: sinks, `update` and `get_snapshot` read and write the same
`State` with plain stores (`input_default.zig:18-36`). Callers must not overlap them.

## How the window feeds the sinks

`ke_window_glfw` takes a borrowed, nullable `ke_input *` in its params
(`src/zig/window/glfw/src/core.zig:13-21`). `window.poll_events` calls `glfwPollEvents`, and the
callbacks it triggers reach `handleEvent`, which forwards each key, button, motion and scroll event
to the matching sink (`core.zig:89-96`, `124-141`). With a null input the events are dropped
(`core.zig:126`). The managed `AddGlfwWindow` fills that field from `INativeInput` if one is
registered **at the moment the window singleton is first resolved**, and from nothing otherwise
(`src/csharp/window/KernelEngine.Window.Glfw/ServiceCollectionExtensions.cs:51-56`).

## One tick in the managed host

The host calls `window.PollEvents()` on the thread that created the window, then `runtime.Tick`
(`examples/csharp/00_runtime_minimal/Program.cs`). The window module registers no system, so the
sink calls of a poll can never interleave with the tick.

In the tick, `Scene.Input` (registered by `OnLoad` of a runtime module, in `PreUpdate`) calls
`input.Update()`, then `input.CaptureSnapshot()` (a `get_snapshot` wrapped in an `IInputReader`),
stores it in a field, then calls `evaluator.Evaluate(snapshot)`. It is pinned to worker 1 and
declares an empty access list (`src/csharp/framework/KernelEngine.Framework/Modules/SceneNodesModule.cs:82-87`).

The snapshot field is what every later reader sees for the rest of the tick. `Scene.Behaviors.*`
systems run in `Update`, which starts only after `PreUpdate` has finished
([runtime.md](runtime.md)), and receive the snapshot in their `View`
(`SceneNodesModule.cs:141`; `Scene/View.cs:37-43`). `View.IsKeyDown` and `View.IsKeyJustPressed`
read the snapshot's `down` and `pressed` bits. The action evaluator's state, evaluated once by `Scene.Input`,
is read by `IInputActionMap` (`Input/InputActionMap.cs:50-59`).

`FixedUpdate` runs between the two phases, zero or more times per tick
([runtime.md](runtime.md#fixed-timestep)). Each such run sees the same snapshot and the same action
state, so an edge visible in one is visible in all of them in that tick.

## Actions are not edges of the snapshot

The action layer reads the snapshot's `keys_down` and `mouse_buttons_down` bitsets and nothing else
(`src/zig/framework/src/input_actions.zig:230-239`, `255-271`). It derives its own `pressed` and
`released` by comparing the value of the previous `evaluate` call with this one
(`input_actions.zig:544-548`, `623-633`). Its edges therefore last until the next `evaluate`, and a
key pressed and released between two evaluations is not seen at all, where the snapshot's
`keys_pressed` would have it.

The managed `InputActionMap.Evaluate` passes no event callback (`InputActionMap.cs:44-46`), which the
native contract defines as "update polling state only" (`src/c/framework/kernel_engine/framework/input_actions.h:68-70`). So the
STARTED, PERFORMED and CANCELED events of `ke_input_action_event` are never delivered to managed
code; polling is the only managed read path.

When an `IActionEvaluator` is registered but no `IInput` is, `Scene.Input` still calls `Evaluate`
with a null reader; the managed map forwards a null snapshot and the native call fails with
`KE_ERROR_INVALID_ARGUMENT` (`SceneNodesModule.cs:84-86`, `InputActionMap.cs:44`,
`input_actions.zig:532-535`), which the generated wrapper throws.

## What nothing reads

`IInput.DrainEvents` and the native event queue behind it have no caller outside the wrapper itself
(`grep -rn 'DrainEvents' src examples --include='*.cs'` finds the declaration and the implementation).
Only the snapshot and the action map are consumed.
