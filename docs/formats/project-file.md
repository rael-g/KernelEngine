# Project file

The Project file is a TOML file named `Project`, with no extension, in the project directory the
SDK is given (`DefaultEngine.Create`, `DefaultCore.AddDefaultCore`).
The engine loads it into the `ke_configuration` store; how that works is in
`architecture/configuration.md`. This document says how a key is addressed and which part reads it.

## How a key is addressed

A table is a section; a nested table joins the path with a dot, so `[runtime.window]` is section
`runtime.window`. An array of tables becomes one section per element, named by the array's key and
the element's index; an array of values becomes one key per element in the same section, named the
same way, so `clear_color = [0.04, 0.04, 0.08, 1.0]` is the keys `clear_color.0` to `clear_color.3`
(`walkArrayOfTables`, `walkArrayOfValues`, `src/zig/configuration/toml/src/configuration_toml.zig`).

The store accepts whatever the file says. A part checks its own section when it is made: a key it
does not know, a value of another type or out of range refuses the creation, with a warning naming
the key (`settings_schema`, `src/zig/settings/schema/settings_schema.zig`).

## Which part reads a section

Each part is made with its section as `ke_settings` and reads the keys its contract declares
(`KE_<DOMAIN>_SETTING_*`) and those its plugin declares in its settings struct, with the plugin's
default for an absent key. The sections the SDKs hand to the default parts:

| section | part | keys |
|---|---|---|
| `runtime.window` | the window | `title`, `width`, `height`, `fullscreen` |
| `runtime.renderer.device` | the GPU device | `enable_validation`, `debug_labels` |
| `runtime.renderer` | the window render target | `present_mode` (`fifo`, `mailbox` or `immediate`) |
| `runtime.physics_2d` | the 2D physics world | `gravity_x`, `gravity_y` |
| `ecs` | each ecs world | `reserved_id_capacity` |
| `schedule` | each schedule | `refuse_ambiguity` |
| `scheduler` | the scheduler | `fixed_dt`, `fixed_dt_max_accum` |
| `render` | the render frame | `clear_color` |
| `render.shadow` | the shadow pass | `resolution`, `light_distance`, `extent`, `near_plane`, `far_plane` |
| `render.cluster` | the cluster pass | `grid_x`, `grid_y`, `grid_z`, `max_lights_per_cluster` |
| `render.deferred_lighting`, `render.forward` | the lighting passes | `ibl_enabled` |
| `input` | the input actions | the maps, actions and bindings under `input.map` |
| `project` | `Engine.Run` | `default_scene`, the scene it opens without an argument |

The job and async systems are made before the file is loaded, so the SDKs do not give them a section
of it.
