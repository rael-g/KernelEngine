# 22 — Input Action Layer

> **Status**: 📋 Architectural decision. Not implemented yet (current input is keys-and-buttons direct, see [Tier C of the Framework Kanban](../Kanban.md#tier-c--high-level-input)). This chapter freezes the design before the first line of action-layer code so we do not inherit Unity Antigo's mistake: tying game logic to physical inputs.

## 1. The lesson from Unity

Unity recently deprecated its old input API (`UnityEngine.Input`). The root cause of the deprecation is worth burning in:

> **Game logic that knows about physical inputs ages badly.**

The old API:

```csharp
if (Input.GetKey(KeyCode.W))  Move(Vector3.forward);
float h = Input.GetAxis("Horizontal");    // ← string identifier
if (Input.GetMouseButtonDown(0)) Fire();
```

Failures it forced:
1. **Magic string identifiers** — `"Horizontal"` had no autocomplete; a typo failed silently.
2. **Device coupling** — `KeyCode.W` is a key, not an intention. Adding gamepad support meant duplicating every input branch.
3. **No action concept** — `Jump` did not exist as a first-class thing; `Space` did.
4. **No rebinding** — every game rewrote its own "press a key to remap" UI from scratch.
5. **No context maps** — the game could not tell input "menu is open, gameplay actions are paused."
6. **Polling-only edges** — `GetKeyDown` was edge-detection over an internal state diff, not events.
7. **Multi-device fragmentation** — touch, gamepad, mouse each had its own parallel API.

The new Input System is built around **Actions**:

```csharp
[InputAction("Jump")] InputAction jumpAction;
if (jumpAction.WasPressedThisFrame()) Jump();
// Bindings (in an .inputactions asset): Jump ← Keyboard/Space, Gamepad/SouthButton, Touch/Tap
```

The pivot: game logic talks to **abstract verbs** (`Jump`, `Move`, `Aim`). Hardware bindings are data, not code.

## 2. Where KernelEngine stands

Aligned with the new model (and ahead of Unity Antigo):

- ✅ **Typed enums.** `Key.Space` / `MouseButton.Left`, not strings.
- ✅ **Real event stream.** `Node.OnInput(InputEvent)` since Tier 2 Slice 4 — proper queue, no edge-from-diffing.
- ✅ **Tree dispatch with `evt.Consume()`** — Godot-signal-style propagation.
- ✅ **Polling coexists.** `IInputReader.IsKeyDown(Key.W)` for level state.
- ✅ **DI-injected.** Testable, mockable, not a global singleton.

Not yet aligned (and where Unity Antigo died):

- ❌ **No action layer.** Game code references `Key.Space` directly today — same trap.
- ❌ **No action maps / contexts.** No "Gameplay map active, UI map suspended".
- ❌ **No composite bindings.** Players wire WASD-as-Vector2 by hand in `OnUpdate`.
- ❌ **No gamepad/joystick support.** GLFW supports them, but `ke_input` only forwards keyboard/mouse callbacks today.
- ❌ **No runtime rebinding.** Settings UI for player remap = not possible without writing the layer.
- ❌ **No multi-device / hot-plug.** One keyboard + one mouse assumed.

The non-negotiable rule going forward: **add the action layer BEFORE gamepad / additional devices**. Order matters. If we ship gamepad without the action layer, every example reimplements the abstraction case by case — we recreate Unity Antigo's pain in our own engine.

## 3. The architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Game code — speaks Actions, never physical inputs.                       │
│  input.IsActionDown(GameAction.MoveForward)                               │
│  input.GetActionVector2(GameAction.Move)                                  │
│  node.OnInputAction(ref InputActionEvent evt)                             │
├──────────────────────────────────────────────────────────────────────────┤
│  InputActionMap — collection of actions, can be activated/deactivated.    │
│  Multiple maps coexist; the active set decides what fires.                │
├──────────────────────────────────────────────────────────────────────────┤
│  InputBinding — maps an Action to one or more physical controls.          │
│  Composite bindings (Vector2 from 4 keys, etc.).                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Device layer — Key, MouseButton (today), GamepadButton/Axis, Touch…      │
│  Driven by InputEvent stream from ke_input.                               │
└──────────────────────────────────────────────────────────────────────────┘
```

Each layer only knows about the one immediately below it. Game code never reaches past `InputAction`.

## 4. Action shape

Actions have **types** (matching the kind of value they produce):

| ActionType | C# value     | Typical bindings |
|---|---|---|
| `Button`   | `bool` (pressed-this-frame, released-this-frame, currently down) | Key, mouse button, gamepad button |
| `Axis1D`   | `float -1..1` | Joystick axis, mouse scroll-Y, key pair (A/D = -1/+1) |
| `Axis2D`   | `Vector2`     | Joystick stick, mouse delta, composite WASD |
| `Axis3D`   | `Vector3`     | (rare — VR controllers, 6DoF input) |

Game code uses **strongly-typed enum** identifiers (no strings):

```csharp
public enum GameAction
{
    MoveForward,
    MoveBackward,
    Move,        // Vector2 composite
    Jump,
    Fire,
    Pause,
}

// Polling
if (input.IsActionDown(GameAction.Jump)) ...
var move = input.GetActionVector2(GameAction.Move);

// Or events on a Node
protected override void OnInputAction(ref InputActionEvent evt)
{
    if (evt.Action == GameAction.Jump && evt.Phase == ActionPhase.Started) Jump();
}
```

Strings are reserved for tooling/CLI/agent surface (capability database — see chapter 20). At runtime we type-check.

## 5. Bindings

A binding maps an action to one or more physical inputs. Multiple bindings per action are first-class.

```csharp
var map = new InputActionMap("gameplay");
map.AddAction(GameAction.Jump, ActionType.Button)
   .AddBinding(Key.Space)
   .AddBinding(GamepadButton.South);    // future device

map.AddAction(GameAction.Move, ActionType.Axis2D)
   .AddComposite(Vector2Composite.WASD())
   .AddBinding(GamepadAxis.LeftStick)
   .AddBinding(TouchVirtualJoystick.Default);
```

Composite bindings produce a derived value from multiple primitives:

| Composite              | Output      | Inputs |
|---|---|---|
| `Vector2Composite.WASD()`        | `Vector2` | W/A/S/D → (0,1)/(-1,0)/(0,-1)/(1,0) |
| `Vector2Composite.Arrows()`      | `Vector2` | Up/Left/Down/Right arrows |
| `Vector1Composite.KeyPair(neg, pos)` | `float`   | Two keys mapped to -1 / +1 |
| `Vector2Composite.MouseDelta()`  | `Vector2` | Mouse movement (already a delta) |

Custom composites are pluggable later.

## 6. Action Maps & contexts

```csharp
var gameplay = new InputActionMap("gameplay");
var ui       = new InputActionMap("ui");

// Both registered; only one active at a time (or stacked — see below)
input.ActivateMap(gameplay);

// Player opens menu:
input.PushMap(ui);          // stack: [gameplay, ui], gameplay paused
// Player closes menu:
input.PopMap();             // back to gameplay
```

Stack discipline (push/pop) is more useful than flat activation — "open inventory" temporarily takes over without losing the previous context. Same model the Editor Lib uses for transactions (chapter 18 §6).

Map switching is **the only correct way to "pause input"** in a context. Adding `if (paused) return;` checks at every action site is a leak of game state into input plumbing.

## 7. Runtime rebinding

Built into the action layer, not a feature an individual game implements:

```csharp
var rebind = input.StartRebinding(GameAction.Jump);
rebind.OnComplete = result =>
{
    if (result.Cancelled) return;
    Console.WriteLine($"Jump rebound to {result.Control}");
    input.SaveBindings("user_bindings.toml");
};
// UI shows "Press any key for Jump..."; player presses → rebind fires.
```

Bindings persist as data (`user_bindings.toml` — chapter 15 sibling). The map definition stays in code/asset (defaults); user overrides shallow-merge on top, identical to the configuration service overlay pattern (chapter 16 §2.4).

## 8. Devices

Devices come from the same `ke_input` source we use today, but the action layer treats them uniformly:

- **Keyboard, mouse** — already supported.
- **Gamepad/joystick** — extend `ke_input` with `on_gamepad_*` sinks; GLFW supports them.
- **Touch** — when mobile arrives. GLFW does not; would come from a different window plugin (SDL or platform-native).
- **VR controllers** — when/if XR plugins ship.

The action layer is **device-agnostic by design**. Adding a new device = teaching `ke_input` to forward its events; existing actions get a new binding option. Zero game-code change.

Hot-plug: when a gamepad is connected mid-session, the device layer emits a `DeviceConnected` event. Active maps that have gamepad bindings start accepting input from it automatically.

## 9. Multi-device

Local co-op: 4 gamepads, 1 keyboard, all addressable individually:

```csharp
foreach (var device in input.Devices.Where(d => d.Kind == DeviceKind.Gamepad))
{
    var player = SpawnPlayer();
    var map = player.GetComponent<PlayerInputMap>();
    map.PairWith(device);                 // this map only reacts to this device
}
```

A map paired with a specific device ignores input from others. Multiple maps over multiple devices = couch co-op for free.

## 10. Fixing the snapshot edge-poll unreliability

`IsKeyPressed` (edge poll) is unreliable today (OBS.5 §3 in the Kanban). Root cause: `InputBuffer` is a single-slot exchange — when ke.main publishes faster than ke.sim consumes, the older snapshot is overwritten and a `keys_pressed` bit that fired briefly is lost.

The action layer fixes this **by construction**:

- `WasActionPressed(action)` / `WasActionReleased(action)` are derived from the **event stream** drained per frame, not from a snapshot bitset.
- The event stream is the kernel ring buffer + cross-thread queue from Slice 4 — accumulates, never loses entries.
- The legacy `IsKeyPressed(Key)` / `IsKeyReleased(Key)` polling stays for backward compat but is marked obsolete; the docs steer new code at the action API.

`IsKeyDown` / `IsActionDown` (level polling) stay fully reliable because they read steady state, not edges.

## 11. Implementation order (when work begins)

`F.C2` in the Kanban becomes:

1. **Core types** — `InputAction`, `InputActionMap`, `InputBinding`, `Vector2Composite.WASD()` etc.
2. **Polling API** — `IsActionDown`, `WasActionPressed`, `GetActionVector2` derived from the event stream.
3. **Event API** — `Node.OnInputAction(ref InputActionEvent evt)`, dispatched alongside `OnInput`.
4. **Map stack** — `ActivateMap`, `PushMap`, `PopMap`.
5. **Persistence** — bindings serializable to `user_bindings.toml`; defaults in code/asset.
6. **Gamepad** — extend `ke_input` with gamepad sinks; ship `GamepadButton`/`GamepadAxis` enums.
7. **Rebinding** — `StartRebinding(action)` API.
8. **Multi-device** — `PairWith(device)`, `DeviceConnected` events.

Steps 1-3 are the architectural commitment — once they land, every subsequent device/feature plugs in without disturbing game code. Steps 4-8 are incremental.

## 12. What this is NOT

- **Not a complete rewrite of input.** The existing event + polling APIs stay. The action layer sits on top.
- **Not an input-mapping editor UI.** That is a frontend concern (eventual GUI editor). The CLI / library exposes the data; visual editing is layered on top later.
- **Not a virtual joystick / on-screen button system.** Those are touch-specific UI nodes, separate concern.
- **Not gesture recognition.** Swipe, pinch, etc. are higher-level — would build on top of action events once they exist.

## 13. Cross-references

- The existing event infrastructure this builds on: [06 - Framework](06%20-%20Framework.md), Tier 2 Slice 4 commits (`c654577`).
- Persistence pattern for `user_bindings.toml`: [15 - Serialization & Project Files](15%20-%20Serialization%20%26%20Project%20Files.md), [16 - Configuration Service](16%20-%20Configuration%20Service.md).
- Action enums in the capability database: [20 - Capability Database](20%20-%20Capability%20Database.md).
- Kanban card to expand when work begins: `F.C2 — Input action/axis mapping`.
