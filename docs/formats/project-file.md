# Project file

The Project file is a TOML file named `Project`, with no extension, in the project directory the
SDK is given (`ke_sdk_host_open`, `DefaultProject`).
The engine loads it into the `ke_configuration` store; how that works is in
`architecture/configuration.md`. This document says how a key is addressed and which part reads it.

## How a key is addressed

A table is a section; a nested table joins the path with a dot, so `[actions.map.Pong]` is section
`actions.map.Pong`. An array of tables becomes one section per element, named by the array's key and
the element's index; an array of values becomes one key per element in the same section, named the
same way, so `clear_color = [0.04, 0.04, 0.08, 1.0]` is the keys `clear_color.0` to `clear_color.3`
(`walkArrayOfTables`, `walkArrayOfValues`, `src/zig/configuration/toml/src/configuration_toml.zig`).

The store accepts whatever the file says. A part checks its own section when it is made: a key it
does not know, a value of another type or out of range refuses the creation, with a warning naming
the key (`settings_schema`, `src/zig/configuration/settings_schema/settings_schema.zig`).

## Which part reads a section

Each part is made with its section as `ke_settings` and reads the keys its contract declares
(`KE_<DOMAIN>_SETTING_*`) and those its plugin declares in its settings struct, with the plugin's
default for an absent key. Which section an instance reads is the `section` of the instance in the composition
(`src/sdk/defaults.composition`); an instance with none reads empty settings. The sections of the default
composition:

| section | instance | keys |
|---|---|---|
| `job` | the job system | `worker_count` |
| `window` | the window | `title`, `width`, `height`, `fullscreen` |
| `device` | the GPU device | `enable_validation`, `debug_labels` |
| `target` | the window render target | `present_mode` (`fifo`, `mailbox` or `immediate`) |
| `physics` | the 2D physics world | `gravity_x`, `gravity_y` |
| `ecs` | each ecs world | `reserved_id_capacity` |
| `schedule` | each schedule | `refuse_ambiguity` |
| `scheduler` | the scheduler | `fixed_dt`, `fixed_dt_max_accum` |
| `frame` | the render frame | `clear_color` |
| `deferred_lighting`, `forward` | the lighting passes | `ibl_enabled` |
| `binder`, `service` | the binder and the render service | `shader_dir`, which the SDK writes |
| `labels` | the labels | `default_font`, which the SDK writes |
| `actions` | the input actions | the maps, actions and bindings under `actions.map` |
| `scene_files` | the scene files | `first_scene`, the scene the first tick opens |
