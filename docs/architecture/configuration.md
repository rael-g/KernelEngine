# Configuration

This is a map: the parts of the configuration domain and what each hands on. How a part works
inside is on the generated page of its file. The contract is under `src/c/configuration/`, the
plugins under `src/zig/configuration/`, the managed side under `src/csharp/configuration/`.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| store | `ke_configuration`, made by `ke_configuration_create` | typed writes by section and key | typed reads, and a section as `ke_settings` |
| source | `ke_configuration_source`, made for TOML by `ke_configuration_toml_create` | a store and a file path | writes into the store through its setter slots |
| settings | `ke_settings` under `src/c/settings/`, handed by the store's `section` | a key | its value, or that it is absent or of another type |
| schema | `settings_schema` (`src/zig/settings/schema/`), read by each plugin's factory | a `ke_settings` and the struct of the plugin's settings | the struct filled, with the plugin's defaults for absent keys |
| managed store | `Configuration`, `IConfiguration` | a path through `LoadToml`, and typed writes | typed reads, and `Section` as `PartSettings` |

The store is in the plugin `ke_configuration`, the TOML source in `ke_configuration_toml`; a
source knows the store only through its contract, and another source fits beside it.

## What ties the parts together

**Reads take a fallback.** A getter returns the fallback its caller passes when the key is
missing or holds a value of another type; an integer read as a double is converted.

**The TOML source flattens a file.** A table becomes a section, a nested table a section named by the
path joined with dots, and a key directly under the root has the empty section. An array is
skipped.

**A part reads its section once.** The host hands each factory the section of its part as
`ke_settings`, a borrowed view that reads the store when asked. The factory reads it through
`settings_schema` as it is made: an absent key takes the default the plugin declares, and a key it
does not know, a value of another type or out of range refuses the creation with a warning naming
the key. A value that changes while the part lives is a slot of its contract, not a setting, and the
store calls no one when it is written.

**The file is read once, when the engine is built.** `DefaultCore.AddDefaultCore` loads the project file
into one store before it makes any part that reads it. The job and async systems are made before the
store, since loading it reads the file through them: the C# SDK hands them sections of a separate
"bootstrap" store the host may fill in code, and the C SDK an empty `ke_settings`.

## What the parts agree on without a contract

- The default file is "Project"; a relative path resolves against `AppContext.BaseDirectory`.
- Which section each part receives is chosen by the SDK that makes it; the keys are declared by the
  contract as macros (`KE_WINDOW_SETTING_TITLE`) or by the plugin's settings struct.
- A section name with a dot means a nested table of the file.
