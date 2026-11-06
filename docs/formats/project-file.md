# Project file

The Project file is a TOML file named `Project`, with no extension, next to the executable
(`AddProjectConfig`, `src/csharp/configuration/KernelEngine.Configuration/ServiceCollectionExtensions.cs`).
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

No plugin reads the store. A factory takes its values as a `_config` struct whose defaults its
header names, and its generated `<Class>Config` record is what a host registers, either in code or
from a section of the store it names:

```csharp
.AddConfig(new GlfwWindowConfig { Title = "Pong", Width = 1280, Height = 720 })
.AddConfig<Box2dPhysics2DConfig>("runtime.physics_2d")
.AddConfig<DefaultRenderServiceConfig>("render", config => config with { ShaderDir = shaders })
```

A section's keys are the names of the config's fields; an absent key keeps the field's default, an
enum is written as the name of its value (`present_mode = "fifo"`) and a vector as an array
(`ConfigSectionExtensions`, `src/csharp/configuration/KernelEngine.Configuration/Generated/ConfigSection.g.cs`).
The section a host names is its own choice; the records the engine generates are listed in the
`configs` section of `scripts/api_domains.json`.

Besides those records, `SceneRouterModule` reads `[project] default_scene` and `AddConsoleSink`
reads `[logging] console_level` (`SceneRouterModule.cs`, `Logger/ServiceCollectionExtensions.cs`).

## Keys read only by the command-line tool

The `ke` tool parses the same file with a TOML library of its own, not through the store
(`ProjectManifest`, `src/csharp/cli/KernelEngine.Cli/ProjectManifest.cs`). It reads `ke.modules`,
an array of module ids it edits when it adds or removes a module; `input.actions`, a path to the
`.input` file it appends actions to (`InputActionsFile.cs`); and any dotted path given to its
`get config` and `set config` commands. It finds the file by walking up from the current directory
(or `--project`) for a file named `Project` (`ProjectContext.cs`).
