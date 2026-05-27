# 23 — Audio Logical Layer

> **Status**: 📋 Architectural decision. Not implemented (current audio is path-based and one-shot, see chapter 12 / commit `54c4599`). This chapter freezes the design for the higher-level audio abstractions (categories, pools, buses) so when the beta needs them, the shape is already settled.

## 1. Where the engine is today

Beta slice 3 shipped `IAudio` with the smallest viable surface:

```csharp
var clip = audio.LoadSound("res://sounds/blip.wav");
audio.Play(clip, volume: 0.6f, loop: false);
audio.Stop(clip);
audio.SetMasterVolume(0.5f);
```

This is enough to validate the kernel-vtable-plus-plugin pattern outside render. It is **not** enough for a real game. Three gaps surface immediately when you try to build one:

1. **No variation**. Every footstep, every gunshot, every UI click sounds identical. Real games randomise pitch / pick from 3-5 samples.
2. **No buses**. The player can not set "music = 30%, sfx = 80%, ui = 100%" independently. Master volume is the only knob.
3. **No logical events**. Game code holds raw file handles; the asset path leaks into gameplay logic.

The same anti-pattern Unity Antigo had for input (`KeyCode.W` instead of `Action.MoveForward`) shows up here as `"res://sounds/blip.wav"` instead of `AudioEvent.UIClick`. We do not want to inherit it.

## 2. The three abstractions

Three concepts, each layered cleanly on the previous:

```
┌──────────────────────────────────────────────────────────────────────────┐
│  AudioEvent — "PlayerJump", "UIClick", "ExplosionLarge".                 │
│  Game code triggers events; the engine resolves to clips, pitch, bus.    │
├──────────────────────────────────────────────────────────────────────────┤
│  ClipPool — an event maps to N clips played round-robin or random.       │
│  Per-clip parameters: pitch variance, volume offset, weight.             │
├──────────────────────────────────────────────────────────────────────────┤
│  Bus — Master / Music / SFX / UI / Ambience (configurable).              │
│  Each bus has its own volume + (later) effects (reverb, EQ).             │
├──────────────────────────────────────────────────────────────────────────┤
│  IAudio (current) — load file, play handle. Backed by miniaudio/FMOD.    │
└──────────────────────────────────────────────────────────────────────────┘
```

Game code reaches the top layer; lower layers exist for tooling / advanced use.

## 3. Bus mixer

```csharp
audio.Buses["music"].Volume = 0.3f;
audio.Buses["sfx"].Volume   = 0.8f;
audio.Buses["ui"].Volume    = 1.0f;
```

- **Built-in buses** by convention: `master`, `music`, `sfx`, `ui`, `ambience`. Projects can add more.
- Bus volumes are **multiplicative** down a chain (a bus can have a parent bus eventually — flat for v1, hierarchical later).
- Bus volumes **persist** to `user_settings.toml` automatically (chapter 16 sibling). Player's volume preferences survive restarts.
- Master volume is the existing `IAudio.SetMasterVolume` — internally just the master bus.

Buses are also where **effects** live in the long run (reverb, EQ, compression). Not v1, but the bus abstraction is where they will plug in. Designing it now keeps the door open.

## 4. Logical events

```toml
# resources/audio/player_jump.event
[event]
name   = "PlayerJump"
bus    = "sfx"

[[event.clip]]
path           = "res://sounds/jump_1.wav"
weight         = 1.0
pitch_variance = 0.1     # ±10% random pitch per play

[[event.clip]]
path           = "res://sounds/jump_2.wav"
weight         = 1.0
pitch_variance = 0.1

[[event.clip]]
path           = "res://sounds/jump_3.wav"
weight         = 0.5     # half as likely as the others
pitch_variance = 0.1

[event.volume]
base           = 0.7
random_offset  = 0.1     # ±10% volume jitter
```

Game code:

```csharp
audio.Trigger("PlayerJump");
// → engine picks weighted-random clip, applies pitch+volume variance, plays on sfx bus
```

Or strongly-typed (the project's capability database — chapter 20 — lists known events, an enum gets generated):

```csharp
audio.Trigger(AudioEvent.PlayerJump);
```

**Variants without code change**: artist drops three new jump sounds into `resources/audio/`, edits the `.event` file to list them, restart. No game-code recompile.

## 5. ClipPool details

The pool semantics are decided per event:

| Mode             | Behaviour |
|---|---|
| `random_weighted`  | Pick by weights; default. |
| `random_no_repeat` | Random, but never the same clip twice in a row. |
| `round_robin`      | Cycle through clips in order. |
| `single`           | One clip; no pool (sugar for the common one-clip case). |

Pitch and volume variance always apply per-play; the pool decides *which* clip plays.

## 6. Spatial audio (3D positional)

Out of scope for this chapter — a separate slice when 3D scenes need it. Outline only:

- `audio.Trigger(event, source: nodeTransform)` — emits from a position; engine attenuates by distance + applies HRTF.
- `audio.SetListener(camera.Transform)` — player's ears.
- Bus mixing happens after spatialization; UI bus stays 2D.

3D positional rides on the same event/pool/bus layers — no separate API surface. Adding 3D = adding parameters to the play call, not a parallel system.

## 7. Streaming vs in-memory

For v1 every clip is decoded fully into RAM at load time (current `IAudio.LoadSound`). Streaming (load-on-demand from disk for long music tracks) is a clip property:

```toml
[[event.clip]]
path     = "res://music/level_theme.ogg"
stream   = true     # load on demand; default false
```

The backend (miniaudio) handles streaming internally; the event/pool/bus layers do not care.

## 8. Persistence of user settings

Bus volumes live in `user_settings.toml` — the gitignored sibling of `Project` (chapter 15 §7). Pattern:

```toml
# user_settings.toml (gitignored)
[audio.buses]
master = 0.8
music  = 0.3
sfx    = 0.8
ui     = 1.0
```

Auto-saved on change (debounced), auto-loaded at boot. Same overlay pattern as `User.local` for runtime config (chapter 16 §2.4).

## 9. What this is NOT

- **Not a DAW.** No fades, ducking automation, arrangement timelines, audio scripting language.
- **Not procedural audio.** Synthesis stays in game code (the example 15 sine-WAV trick is a test helper, not engine API).
- **Not voice / mic capture.** Different domain entirely; new kernel contract when needed.
- **Not VST hosting / effect plugins.** Buses will host built-in effects (reverb, EQ); third-party effects are far-future.

## 10. Implementation order (when work begins)

This chapter does not get a single Kanban card — it is a sequence of smaller slices on top of beta:

1. **Bus mixer** — minimal: 5 named buses, per-bus volume, persistence to `user_settings.toml`. ~1 day.
2. **ClipPool primitive** — `IAudio.PlayPool(handles[], mode)` taking pre-loaded sounds. No file format yet. ~half day.
3. **`.event` TOML file format + loader** — sits next to `.material` loaders (chapter 17 §6). ~1 day.
4. **`audio.Trigger(name)` API** — looks up `.event`, applies pool + pitch/volume jitter, dispatches to bus. ~half day.
5. **Capability database wires `AudioEvent` enum gen** — chapter 20 extension. Optional ergonomics. ~half day.
6. **Spatial audio** — separate slice when 3D gameplay needs it. ~2-3 days.
7. **Bus effects** — far future. ~weeks.

Total to "ready for a real game" excluding spatial: ~3-4 days. Beta does not strictly need any of it; first complete-game example (Pong, beta #5) ships with the current minimal API. The moment the example after that wants footstep variety or a music/SFX volume slider, this chapter unblocks.

## 11. Cross-references

- The current audio plumbing this layers on top of: [09 - Assets & Pipelines](09%20-%20Assets%20%26%20Pipelines.md), commit `54c4599`.
- Asset-file pattern (`.event` follows `.material`): [15 - Serialization & Project Files](15%20-%20Serialization%20%26%20Project%20Files.md).
- User-settings persistence pattern: [16 - Configuration Service](16%20-%20Configuration%20Service.md) §2.4 overlay.
- Capability-database enum generation (`AudioEvent`): [20 - Capability Database](20%20-%20Capability%20Database.md).
