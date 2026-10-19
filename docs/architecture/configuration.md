# Configuration

This is a map: the parts of the configuration domain and what each hands on. How a part works
inside is on the generated page of its file. The contract is under `src/c/configuration/`, the
plugins under `src/zig/configuration/`, the managed side under `src/csharp/configuration/`.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| store | `ke_configuration`, made by `ke_configuration_create` | typed writes by section and key | typed reads, and a call to each subscriber of a written section |
| source | `ke_configuration_source`, made for TOML by `ke_configuration_toml_create` | a store and a file path | writes into the store through its setter slots |
| managed store | `Configuration`, `IConfiguration` | a path through `LoadToml`, and typed writes | typed reads |
| registration | `AddProjectConfig`, `TryAddConfigurationSingleton` | an optional path | the `IConfiguration` singleton |

The store is in the plugin `ke_configuration`, the TOML source in `ke_configuration_toml`; a
source knows the store only through its contract, and another source fits beside it.

## What ties the parts together

**Reads take a fallback.** A getter returns the fallback its caller passes when the key is
missing or holds a value of another type; an integer read as a double is converted.

**The TOML source flattens a file.** A table becomes a section, a nested table a section named by the
path joined with dots, and a key directly under the root has the empty section. An array is
skipped, which is why `GetFloatArray` and `SetFloatArray` use the keys `key_0`, `key_1`, and so on.

**A write calls the subscribers of its section.** They run on the writing thread, after the
value is stored, and receive the section, not the key. `Configuration` has no subscribe member.

**The file is read once, on first resolution.** `TryAddConfigurationSingleton` registers the
singleton only if none is registered, so the first registration decides the path. Modules read
their keys when they are built or loaded and keep the result.

## What the parts agree on without a contract

- The default file is "Project"; a relative path resolves against `AppContext.BaseDirectory`.
- The sections and keys each reader asks for ("logging" and "console_level" for the logger, and
  those of the window, physics and render modules) are in those readers, not in a header.
- A section name with a dot means a nested table of the file.
