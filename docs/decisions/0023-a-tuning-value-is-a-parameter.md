# 0023. A tuning value is a parameter with a default, not a constant

Recorded: 2026-10-13. The decision is older than this record.

## Context

A buffer size, a cap per bucket or a grid resolution written as a constant is a ceiling the engine
imposes on every game. When a game exceeds it the result is a hard failure or a visible artifact,
and the only remedy is editing the engine.

## Decision

A number stays a bare constant only when the algorithm implies it. Any other is a field of a params
struct or an argument of the factory, with the measured value kept as the default.

## Consequences

- A stress test finds a sane default; it does not justify a ceiling.
- Only what was shown to matter is promoted, so factories are not flooded with fields nobody sets.
- Remaining constants of this kind are debt; a machine cannot tell them from the implied ones, so no
  gate counts them.
