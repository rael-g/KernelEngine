# Project file

The Project file is a TOML file named `Project`, with no extension, in the project directory the
SDK is built from (`EngineBuilder.Build`).
The engine loads it into the `ke_configuration` store; how that works is in
`architecture/configuration.md`. This document says how a key is addressed and which code reads it.

## How a key is addressed

A table is a section; a nested table joins the path with a dot, so `[runtime.window]` is section
`runtime.window`. An array of tables becomes one section per element, named by the array's key and
the element's index; an array of values becomes one key per element in the same section, named the
same way, so `clear_color = [0.04, 0.04, 0.08, 1.0]` is the keys `clear_color.0` to `clear_color.3`
(`walkArrayOfTables`, `walkArrayOfValues`, `src/zig/configuration/toml/src/configuration_toml.zig`).

An unknown key is not an error. The store accepts whatever the file says, and nothing checks the
file against a list of keys.

## Which code reads a section

No plugin reads the store. A factory takes its values as its `_config` struct, filled completely by
the host. The C# SDK fills them from the store as it makes each part, and the C Pong does the same
by hand; the keys the SDK reads are:

| section | keys | read for |
|---|---|---|
| `runtime.window` | `title`, `width`, `height`, `fullscreen` | the window |
| `runtime` | `fixed_dt`, `fixed_dt_max_accum`, `max_systems_per_phase` | the runtime |
| `runtime.renderer` | `present_mode` (`fifo` or `mailbox`) | the window render target |
| `runtime.physics_2d` | `gravity_x`, `gravity_y` | the 2D physics world |
| `render` | `clear_color` | the render service |
| `project` | `default_scene` | the scene `Engine.Run` opens without an argument |
| `input` | the maps, actions and bindings under `input.map` | the input actions |
