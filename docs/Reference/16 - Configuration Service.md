# 16 — Configuration Service

> **Status**: 📋 Architectural decision — **partially superseded 2026-07-02.** This chapter froze the *shape* of the config service as a **C#-only** service (`IProjectConfig` + `IOptions<T>` via `Microsoft.Extensions.Options`). Two decisions here are **reversed** by the native-config decision (authoritative source: [`RenderArchitectureV2.md` §9.9](../RenderArchitectureV2.md)):
> - **§2 framing (C#/`IOptions<T>`)** → configuration is now a **native `ke_configuration` C-ABI contract** (kernel primitive + TOML loader plugin); C# becomes a thin wrapper. This is a **multi-language engine — C# is not special**, and settings are too important to be C#-exclusive.
> - **§2.3 (boot-time snapshot, `IOptionsMonitor` rejected)** → **reversed.** Runtime change *is* supported, opt-in per module, via a native change subscription (the `IOptionsMonitor.OnChange` equivalent). Applied at the owning system's own execution point, never on the callback thread, never via pinning.
>
> The **still-valid** decisions below: §2.1 (plugins own their settings POCO/struct), §2.2 (plugins depend on config, not vice-versa), §2.4 (defaults live on the POCO/params), §2.5 (typed + stringly-typed access), §2.6 (section→type mapping). Read those as the enduring shape; read §2 framing and §2.3 through the amendment above.

## 1. The problem

Today, every example wires the engine in code:

```csharp
services.AddGlfwWindow(1280, 720, "MyGame")
        .AddBgfxRenderer("shaders");
```

Knobs are scattered across `AddX(...)` calls. Changing the window size means editing C#. There is no single place a developer (or agent, or future GUI editor) can read or write engine settings.

`Project` (chapter 15) is the *file format* answer. This chapter defines the *runtime service* that loads it and feeds it into the rest of the engine.

## 2. The six decisions

The architecture is fully specified by six choices. Each one has alternatives we considered and rejected; the decision is recorded with rationale so future reopening is informed.

### 2.1 Schema ownership — plugins own their settings

Each plugin defines its own settings POCO. The configuration service does not declare what fields a plugin needs.

```csharp
// Inside KernelEngine.Window.Glfw
public sealed class WindowOptions
{
    public int    Width      { get; set; } = 1280;
    public int    Height     { get; set; } = 720;
    public string Title      { get; set; } = "KernelEngine";
    public bool   Fullscreen { get; set; } = false;
    public bool   Vsync      { get; set; } = true;
}
```

**Rejected:** central schema where the config service declares every setting (string-keyed, à la Godot `ProjectSettings`). Forces every plugin change to ripple through a central declaration. Loses static type-checking.

**Trade-off accepted:** type safety and plugin autonomy over centralized discoverability. We get discoverability back via §2.5 (stringly-typed access alongside the typed surface).

### 2.2 DI dependency direction — plugins depend on the config service

Registration order: configuration first, plugins second.

```csharp
services
    .AddProjectConfig("Project")   // singleton, registered first
    .AddGlfwWindow()                    // injects IOptions<WindowOptions>
    .AddBgfxRenderer();                 // injects IOptions<BgfxRendererOptions>
```

A plugin's factory pulls `IOptions<XxxOptions>` from DI and uses the values to construct itself. Plugins know about the config service; the config service knows nothing about any specific plugin.

**Rejected (the inversion):** "configuration service depends on plugins, applies values after everything is registered". Sounds clean but forces the config service to know each plugin's setter API — that is hub-and-spoke coupling. The chosen direction keeps the config service generic; plugins are interchangeable.

**Rejected (manual passthrough):** keep `AddGlfwWindow(1280, 720, "Title")` and have a separate loader that calls it with values from TOML. Just moves the wiring code, doesn't centralize anything.

### 2.3 Mutability — boot-time snapshot, not reactive

The configuration service is read once at startup. Values flow into plugins at construction. Changing a value in the service later does not propagate.

Runtime mutation goes through the plugin's own API:

```csharp
window.SetFullscreen(true);   // ✅ live change
config.Window.Fullscreen = true; // ❌ no effect on a running window
```

When a developer wants to *persist* the live state back to disk, the editor lib offers `config.Snapshot()` to capture the current state of all plugins and `config.Save()` to write it back to `Project`. That is a deliberate save, not a reactive sync.

**Rejected (originally) — REVERSED 2026-07-02:** this section originally rejected `IOptionsMonitor<T>` change notifications as covering "maybe 10% of use cases". That call is overturned: runtime reconfiguration (e.g. a settings menu changing shadow resolution) is now a first-class, **opt-in per module** capability via the native change subscription (`ke_configuration.subscribe`, the `OnChange` equivalent). The "which frame does this apply on / reentrancy" hazards the original rejection named are real and are answered by the **latch-then-apply** rule: the callback only latches a pending value; the module applies it at the top of its *own* system's next run, where the wave-builder already grants exclusive access to the affected resource — no cross-thread GPU mutation, no pinning. Authoritative: [`RenderArchitectureV2.md` §9.9](../RenderArchitectureV2.md). Boot-time-only modules simply never subscribe and keep the original snapshot behavior.

### 2.4 Defaults — the plugin's Options POCO is the default

Defaults live as initializers on the POCO (see §2.1: `Width = 1280` directly on the property). The configuration service does not maintain a default catalog.

Load semantics:
1. Construct `WindowOptions` with C# defaults.
2. Apply values from `Project.[runtime.window]` on top, where present.
3. Apply values from `User.local.[runtime.overrides.window]` on top of that.
4. Hand to plugin.

Missing TOML section → plugin gets full defaults. Missing field within a section → that field keeps its default. **No setting is ever required in `Project`** unless the plugin genuinely cannot function without it (e.g. shader path for the renderer).

**Rejected:** central defaults registry. Adds a maintenance point that drifts from the POCO.
**Rejected:** fail-fast on missing settings. Makes greenfield development painful and forces TOML files to mention every setting just to keep working.

### 2.5 Stringly-typed access alongside typed access

The same backing store is accessible two ways:

```csharp
// Plugin-side (typed, the common path):
public sealed class GlfwWindowFactory(IOptions<WindowOptions> opts)
{
    public IWindow Build() => new GlfwWindow(opts.Value.Width, opts.Value.Height, ...);
}

// Tooling / CLI / agent side (stringly, for introspection):
config.GetValue<int>("window.width")         // → 1280
config.SetValue("window.fullscreen", true)
config.ListAll()                              // → IEnumerable<(string key, object value)>
```

The CLI uses the string surface (`ke config get window.width`, `ke config set window.fullscreen true`). Agents use it for introspection. Game code uses the typed surface.

Both views read from the same store; setting via the string surface mutates the same backing POCOs (with the caveats of §2.3 — the change does not propagate to running plugins, just to the in-memory config that a future `Save()` would persist).

### 2.6 Mapping from TOML section to Options type

By convention, the TOML path `[runtime.window]` binds to `WindowOptions`. The mapping is registered when the plugin's DI extension calls `AddProjectConfigSection`:

```csharp
// Inside the plugin's ServiceCollectionExtensions:
public static IServiceCollection AddGlfwWindow(this IServiceCollection services)
{
    services.AddProjectConfigSection<WindowOptions>("runtime.window");
    services.AddSingleton<IWindow, GlfwWindow>();
    return services;
}
```

Plugin declares the path; configuration service handles the hydration. Plugin-specific subkeys (`[runtime.window.platform_specific_thing]`) are still POCO fields.

## 3. Visual summary

```
Project ─┐
              │  ProjectConfig (singleton, registered first)
User.local ───┤   ├─ hydrates → IOptions<WindowOptions>      ← Window plugin
              │   ├─ hydrates → IOptions<BgfxRendererOptions> ← Renderer plugin
              │   └─ hydrates → IOptions<...>                  ← (each plugin)
              │
              └→ also exposes  GetValue("window.width") / SetValue / ListAll
                               (used by CLI, agent, future GUI editor)
```

Boot order:

1. `Application.Run(services)` resolves `IProjectConfig`.
2. `IProjectConfig` parses TOML files and populates registered `IOptions<T>` instances.
3. Plugin factories activate, inject their `IOptions<T>`, construct concrete services.
4. Engine runs normally.

## 4. What this is NOT

- **Not a key-value database.** No persistence beyond `Project` / `User.local`. No transactions, no history.
- **Not a settings UI.** The future GUI editor will read from `IProjectConfig` and call the same `SetValue` / `Save` methods the CLI uses. The config service has no opinions about how settings are presented.
- **Not where game state goes.** Player score, save files, runtime data — none of that. The config service is *engine wiring*, not game data.
- **Not a feature flag system.** Project-wide constants, not per-build feature toggles.

## 5. Open questions (deliberately not decided yet)

These are flagged here so when the work begins we revisit them with context, instead of deciding by accident:

- **Environment / profile overlays.** Per-platform sections like `[runtime.window.linux]` overriding `[runtime.window]`? Yes likely, but the schema isn't pinned.
- **Validation.** Do we run `IValidateOptions<T>` at boot? Probably yes — catch invalid values once at startup rather than crashing on first use. Trivial to add later.
- **Hot reload.** A debug-only option that re-reads `Project` when it changes on disk and re-applies to plugins that *do* opt into reactive updates (i.e. a small whitelist, not §2.3 by default). Useful for tweaking, not on the critical path.

## 6. Implementation order (when work begins)

1. Define `IProjectConfig` + `AddProjectConfig(tomlPath)` in `KernelEngine.Configuration` (new lib).
2. Plumb `IOptions<T>` via Microsoft.Extensions.Options (already a transitive dep via DI).
3. Convert one plugin first (Window) — prove the round trip with a single example.
4. Convert remaining plugins.
5. Add CLI surface (`ke config get/set/list`) on top of the string-keyed accessor.
6. Editor lib's `SaveProject()` round-trips the live config to canonical TOML.

## 7. Cross-references

- The TOML file format the service consumes: [15 - Serialization & Project Files](15%20-%20Serialization%20%26%20Project%20Files.md).
- The editor/CLI/agent layer that reads and writes via this service: [14 - Editor, CLI & Agent Layer](14%20-%20Editor%2C%20CLI%20%26%20Agent%20Layer.md).
- The DI lifecycle this slots into: [06 - Framework](06%20-%20Framework.md) (`Application.Run`).
