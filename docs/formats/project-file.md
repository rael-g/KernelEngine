# Which keys does a Project file have, and who reads each?

The Project file is a TOML file named `Project`, with no extension, next to the executable
(`src/csharp/configuration/KernelEngine.Configuration/ServiceCollectionExtensions.cs:36`; Pong ships
it as a `Content` item copied to the output, `examples/csharp/games/pong/pong.csproj:19-21`). The
engine loads it into the `ke_configuration` store; how that works, and how a value reaches a module,
is in `architecture/configuration.md`. This document is the key list.

## How a key is addressed

A table is a section; a nested table joins the path with a dot, so `[runtime.window]` is section
`runtime.window`. Arrays are not loaded, and neither is any value that is not an integer, float,
boolean or string (`src/zig/configuration/toml/src/configuration_toml.zig:21-37`, `45-59`).
Numeric keys read as `double` must be written with a decimal point: an integer-valued key read as a
double is a type mismatch and yields the reader's fallback (`src/zig/configuration/src/configuration.zig:109-118`).

An unknown key is not an error. The store accepts whatever the file says, and nothing checks the
file against a list of keys.

## Keys the engine reads

| section | key | type | default | reader |
|---|---|---|---|---|
| `project` | `default_scene` | string | `Main` | `SceneRouterModule.ResolveInitialScene`, `SceneRouterModule.cs:79-87` |
| `logging` | `console_level` | string, a `LogLevel` name (case-insensitive); parsed but has no effect on output, see `architecture/logging.md` | `Trace` | `AddConsoleSink`, `Logger/ServiceCollectionExtensions.cs:35-37` |
| `runtime.window` | `width`, `height` | int | 1280, 720 | `AddGlfwWindow`, `Window.Glfw/ServiceCollectionExtensions.cs:24-25` |
| `runtime.window` | `title` | string | `KernelEngine` | same, `:26` |
| `runtime.window` | `fullscreen` | bool | `false` | same, `:27` |
| `runtime.physics_2d` | `gravity_x` | float | `0.0` | `AddBox2D`, `Physics.Box2D/ServiceCollectionExtensions.cs:22` |
| `runtime.physics_2d` | `gravity_y` | float | `-9.81` | same, `:23` |
| `render` | `clear_color_r`, `_g`, `_b`, `_a` | float | 0.10, 0.15, 0.30, 1.0 | `WebgpuRenderModule.ResolveClearColor`, `WebgpuRenderModule.cs:147-156` |
| `render` | `cluster_grid_x`, `_y`, `_z` | int | 0 | `WebgpuRenderModule.OnLoad`, `WebgpuRenderModule.cs:118-120` |
| `render` | `max_lights_per_cluster` | int | 0 | same, `:121-123` |

The `default_scene` value is normalised before use: a leading `res://` and then `scenes/` are
removed, and a trailing `.scene.toml` or `.scene` is removed (`SceneRouterModule.cs:89-97`).
A `logging.console_level` that is not a `LogLevel` name makes `Enum.Parse` throw when the sink is
first resolved (`Logger/ServiceCollectionExtensions.cs:37`).

A `0` for the cluster keys is not a size: it is passed to the render module, which substitutes its
own defaults (`src/zig/render/module/src/render_module.zig:195-209`). `clear_color_*` are four scalars because the loader
skips arrays (`src/zig/configuration/toml/src/configuration_toml.zig:59-60`).

Each of the constructors named above also has an overload that takes the same values inline and
bypasses the file (`AddConsoleSink(LogLevel)`, `AddGlfwWindow(width, height, title)`,
`AddBox2D(gravityX, gravityY)`, `GlfwWindowModule(width, height, title)`); the inline form is the
one that runs when it is used, since it never consults `IConfiguration`
(`Window.Glfw/ServiceCollectionExtensions.cs:37-42`, `GlfwWindowModule.cs:31-41`).

## Keys read only by the command-line tool

The `ke` tool parses the same file with a TOML library of its own, not through the store
(`src/csharp/cli/KernelEngine.Cli/ProjectManifest.cs:26-29`). It reads:

- `ke.modules`, an array of module ids, which it edits when it adds or removes a module
  (`ProjectManifest.cs:31-68`). The engine's loader skips this array, so no runtime code sees it.
- `input.actions`, a path (with an optional `res://` prefix) to the `.input` file it appends actions
  to (`InputActionsFile.cs:24-31`).
- Any dotted path given to its `get config` and `set config` commands (`ProjectManifest.cs:76-100`,
  `Commands.cs:76-83`, `87-95`).

It finds the file by walking up from the current directory (or `--project`) for a file named
`Project` (`ProjectContext.cs:25-33`).

## Keys present in the examples that nothing reads

Pong's and the shadow-map example's Project files (`examples/csharp/games/pong/Project`,
`examples/csharp/06_shadow_map/Project`) carry keys no code reads: `project.name`,
`runtime.renderer.shader_path`, `runtime.renderer.vsync`, `render.ambient_light` (an array, which
the loader skips in any case), and Pong's `input.actions` (read only by the `ke` tool above;
`AddInputActions` takes its path as an argument and defaults to `actions.input` next to the
executable, `src/csharp/framework/KernelEngine.Framework/Input/InputActionsServiceCollectionExtensions.cs:13-21`).
Grep for a section or key string under `src/` before assuming a key has an effect:
`grep -rn '"runtime.renderer"\|"vsync"\|"shader_path"' src --include='*.cs' --include='*.zig'`
finds no reader.
