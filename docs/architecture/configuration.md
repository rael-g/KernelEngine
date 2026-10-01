# How does a Project file reach the value a plugin reads, and how does a change reach it?

Two native plugins and one managed wrapper make the path. `ke_configuration` is a typed
`(section, key) -> value` store (`src/c/configuration/kernel_engine/configuration/configuration.h`,
implemented in `src/zig/configuration/src/configuration.zig`). `ke_configuration_toml_load` fills it
from a TOML file (`src/zig/configuration/toml/src/configuration_toml.zig:67`). `AddProjectConfig`
registers the managed `IConfiguration` over both
(`src/csharp/configuration/KernelEngine.Configuration/ServiceCollectionExtensions.cs:19`).
Which keys the engine reads is in `formats/project-file.md`.

## The store

The store is created by `ke_configuration_create`, which returns a `ke_configuration_handle`
`{ref, destroy}` (`configuration.zig:251-275`). Entries live in one flat list, searched linearly by
exact `(section, key)` (`configuration.zig:50-55`). Each entry holds one of four types: `int`
(`i64`), `double`, `bool`, `string` (`configuration.zig:14-19`).

- **A read never fails.** A missing key, a null section or key, and a key of another type all return
  the fallback the caller passed (`configuration.zig:97-139`). A key stored as an `int` read with
  `get_double` is a type mismatch: it returns the fallback, not a converted value
  (test `type mismatch returns fallback`, `configuration.zig:322`).
- **A write overwrites.** `set_*` replaces the entry's value and type (`configuration.zig:64-68`,
  `141-194`). A null argument fails with `KE_ERROR_INVALID_ARGUMENT`; an allocation failure with
  `KE_ERROR_OUT_OF_MEMORY` (`configuration.zig:142-145`, `70-84`).
- **A string read hands out the store's own pointer**, valid until that key is overwritten or the
  store is destroyed (`configuration.h:28-30`; the old payload is freed by `freeStringPayload`
  inside `upsert`, `configuration.zig:57-68`).
- **There is no synchronisation.** Neither `State` nor any function in the file takes a lock; the
  store is safe only under whatever exclusion its callers provide.

## Loading a file

`ke_configuration_toml_load(cfg, path, out_error)` is a plain exported function in its own plugin
(`configuration_toml.h`), not a vtable slot, and it writes into the store only through that store's
public `set_*` slots (`configuration_toml.zig:20-36`).

- A path that cannot be opened returns `true` and writes nothing (`configuration_toml.zig:72-73`).
- A file that does not parse returns `false` with `KE_ERROR_GENERAL` carrying the tomlc99 message
  (`configuration_toml.zig:77-81`).
- A table becomes a section. A nested table becomes a section named by joining the path with a dot,
  so `[runtime.window]` is section `runtime.window` (`configuration_toml.zig:45-57`). A scalar
  directly under the root has section `""`.
- A scalar is stored by the first type that accepts it, tried in the order int, double, bool, string
  (`configuration_toml.zig:20-34`). `gravity_x = 0` is an int; `gravity_x = 0.0` is a double.
- **Arrays are skipped without a word** (`configuration_toml.zig:58-59`). So are values of any other
  TOML type: `setScalar` falls through to `return true` (`configuration_toml.zig:35`). The store has
  no array type; the managed `GetFloatArray` reads the indexed scalars `key_0`, `key_1`, ... and
  cannot read an authored TOML array (`Configuration.cs:123-135`).
- The loader calls `set_*` for every scalar, so every load notifies subscribers
  (see "Subscribing").

## The managed layer

`Configuration` owns the native handle and exposes `IConfiguration`: `Get*`/`Set*` for the four
types, plus `GetFloatArray`/`SetFloatArray` (`Configuration.cs:12-135`). `Get*` marshal to the
native slot and pass the fallback through. A failed write or load throws the native `ke_error` as a
managed exception (`Configuration.cs:33-34`, `81-82`). `Configuration` has no subscribe member.

`AddProjectConfig(path)` registers `IConfiguration` with `TryAddSingleton`
(`ServiceCollectionExtensions.cs:32`). Three consequences, all from that one call:

- **The file is read on first resolution**, not at registration. The factory builds a
  `Configuration` and calls `LoadToml` (`ServiceCollectionExtensions.cs:34-36`).
- **The first registration wins.** `AddConsoleSink`, `AddGlfwWindow` and `AddBox2D` each call
  `TryAddConfigurationSingleton()` with no path, which registers the default if nothing did before
  (`Logger/ServiceCollectionExtensions.cs:32`, `Window.Glfw/ServiceCollectionExtensions.cs:20`,
  `Physics.Box2D/ServiceCollectionExtensions.cs:18`). A custom `path` passed to `AddProjectConfig`
  takes effect only if that call comes before them.
- **The path.** With no argument the file is `Project`, resolved against
  `AppContext.BaseDirectory`; a relative argument resolves against the same directory, an absolute
  one is used as is (`ServiceCollectionExtensions.cs:36`, `40-45`). A missing file is not an error,
  so every reader's fallback applies.

A host that never registers configuration is legal for readers that use
`services.GetService<IConfiguration>()` and tolerate null: `WebgpuRenderModule` and
`SceneRouterModule` do (`WebgpuRenderModule.cs:115`, `SceneRouterModule.cs:83-84`). Readers that
use `GetRequiredService` fail without it, though each registers the default itself first.

## Subscribing

`subscribe(self, section, cb, ctx)` registers `cb` for writes to exactly that section string and
returns a subscription id, or `KE_CONFIGURATION_SUBSCRIPTION_NONE` (`configuration.zig:196-223`).
`unsubscribe` marks the slot inactive; a later `subscribe` reuses it (`configuration.zig:225-235`).

A write calls every active subscriber of its section **synchronously, on the writing thread, inside
the `set_*` call, after the value is stored** (`notify`, `configuration.zig:88-95`; called at
`149`, `161`, `173`, `192`). The callback receives the section and its `ctx`, not the key and not
the value; it must call a `get_*` to see what changed. There is no comparison: a write of the value
already stored still notifies.

## When a change reaches a module

A subscription is the only way a change is pushed, and nothing outside the configuration plugin
calls `subscribe` (`grep -rn 'subscribe' src --include='*.zig' --include='*.cs'` outside
`src/zig/configuration` and generated code finds no configuration caller). So a module sees a value
exactly when it reads one:

| reader | reads at | cite |
|---|---|---|
| console sink level | the sink singleton's first resolution | `Logger/ServiceCollectionExtensions.cs:35-37` |
| window size, title, fullscreen | the `IWindow` singleton's first resolution | `Window.Glfw/ServiceCollectionExtensions.cs:23-27` |
| Box2D gravity | the `IPhysics2D` singleton's first resolution | `Physics.Box2D/ServiceCollectionExtensions.cs:21-23` |
| render cluster grid, clear colour | `WebgpuRenderModule.OnLoad` | `WebgpuRenderModule.cs:115-124`, `147-156` |
| initial scene | `SceneRouterModule.OnLoad` | `SceneRouterModule.cs:47`, `79-85` |

Each of those reads once and keeps the result. A `Set*` or a second load after that point changes the
store and nothing a module already built from it.
