# 18 — Editor Lib API

> **Status**: 📋 Architectural decision. Not implemented. This chapter pins the shape of `KernelEngine.Editor` — the library that every authoring frontend (GUI editor, CLI, AI agent) consumes. The frontends are interchangeable; the lib is the contract.

## 1. Why one lib

A single library exposing every editor operation is the only way to keep frontends honest. If `ke add node` and the GUI's "Add Node" button can both diverge from each other, they will. With one lib underneath:

- Anything the GUI does, the CLI can do (and vice versa) — by construction.
- Adding a new operation means **exposing it in the lib first**; otherwise no frontend can ship it.
- Testing the editor surface = testing a library. No UI automation, no harness gymnastics.

The lib has no opinions about presentation, threading models of frontends, or interaction styles. It is a service layer.

## 2. Operations by domain

Operations are grouped into five top-level namespaces. Each operation is a method on the corresponding service interface.

```
IEditorSession
  ├─ Project    (IProjectOperations)
  ├─ Scene      (ISceneOperations)
  ├─ Resource   (IResourceOperations)
  ├─ Asset      (IAssetOperations)
  └─ Build      (IBuildOperations)
```

### 2.1 Project

| Operation | Purpose |
|---|---|
| `Create(path, ProjectTemplate)` | Scaffold a new project folder with `Project`. |
| `Open(path)` | Load an existing project; becomes the session's active project. |
| `Save()` | Write any pending changes to `Project`. |
| `Close()` | Release the active project. |
| `GetSettings()` / `SetSettings(...)` | Typed access to `Project` sections via the config service (chapter 16). |

### 2.2 Scene

| Operation | Purpose |
|---|---|
| `Create(name)` | Make a new empty `*.scene`. |
| `Open(path)` | Load a scene into the working set. |
| `Save(path)` / `SaveAll()` | Persist scene(s) to disk. |
| `Close(path)` | Drop from working set. |
| `AddNode(parent, type, name, properties?)` | Adds a node. Returns its handle. |
| `RemoveNode(handle)` | Removes node + descendants. |
| `MoveNode(handle, newParent)` | Reparent. |
| `SetProperty(handle, key, value)` | Single typed property write. |
| `Query(filter)` | Returns matching node handles (e.g. by name pattern, by type). |

### 2.3 Resource

| Operation | Purpose |
|---|---|
| `CreateMaterial(name, params)` | Writes a `*.material`. |
| `CreateSkybox(name, cubemap)` | Writes a `*.skybox`. |
| `Read(path)` / `Update(path, patch)` / `Delete(path)` | CRUD on resource manifests. |

### 2.4 Asset

| Operation | Purpose |
|---|---|
| `Import(sourcePath)` | Trigger import for one binary asset. Async. |
| `Reimport(assetPath)` | Force reimport (e.g. settings changed). Async. |
| `GetImportSettings(assetPath)` / `SetImportSettings(...)` | Read/write the `*.import` sidecar. |
| `List(filter?)` | Enumerate assets in the project. |

### 2.5 Build

| Operation | Purpose |
|---|---|
| `CompileShaders(target?)` | Run the shader compiler over `src/cpp/render/bgfx/shaders/`. Async. |
| `GenerateBindings()` | Run `generate_bindings.py` equivalent. Async. |
| `GenerateClassDatabase()` | Regenerate `class_database.toml` (chapter 20). |
| `Build(target, configuration)` | Full build for a deployment target. Async. |
| `Run(args?)` | Launch the project (forwards to whatever Application.Run does today). |

## 3. Return model

Every operation returns `Result<T, EditorError>` — a discriminated union, never throws on expected failure.

```csharp
public readonly record struct Result<T, E>
{
    public bool IsOk { get; }
    public T Value { get; }     // valid when IsOk
    public E Error { get; }     // valid when !IsOk
}

public sealed record EditorError(
    EditorErrorKind Kind,
    string Message,
    string? Path = null,
    object? Details = null);

public enum EditorErrorKind
{
    NotFound,         // path/handle missing
    Conflict,         // operation collides with existing state
    InvalidInput,     // bad argument
    SchemaMismatch,   // TOML didn't match expected shape
    IOFailure,        // disk/network problem
    Unsupported,      // operation not available in current state
    Cancelled,        // user-cancelled (relevant to async ops)
    Internal,         // genuinely unexpected
}
```

Frontends switch on `Kind` to choose presentation:

```csharp
return result.Error.Kind switch {
    NotFound        => Cli.Red($"not found: {result.Error.Path}"),
    InvalidInput    => Cli.Yellow(result.Error.Message),
    SchemaMismatch  => Cli.Red($"{result.Error.Path}: {result.Error.Message}"),
    _               => Cli.Red(result.Error.Message),
};
```

**Exceptions are reserved for bugs**, not for expected failures. A `NullReferenceException` escaping the lib is a defect; "scene file not found" is a `Result`.

## 4. Sync vs async

Default is synchronous. CRUD on TOML files completes in microseconds; async is overhead without benefit. Long-running operations are explicitly `Task<>` and carry a progress callback.

```csharp
// Synchronous (CRUD on files):
Result<NodeHandle, EditorError> AddNode(...);
Result<Unit, EditorError> SetProperty(...);

// Asynchronous (long-running):
Task<Result<Unit, EditorError>> Import(string path, IProgress<ImportProgress>? progress, CancellationToken ct);
Task<Result<BuildOutput, EditorError>> Build(string target, IProgress<BuildProgress>? progress, CancellationToken ct);
```

Frontends:
- CLI shows a spinner / percentage on stderr; respects `--quiet`.
- GUI threads progress into a panel.
- Agent reads progress as structured events.

## 5. Undo/redo as first-class

Every mutating operation is implemented as an `ICommand`:

```csharp
public interface ICommand
{
    string Description { get; }   // "Add node 'Cube' to scene Level1"
    void Apply();
    void Undo();
}
```

The session owns a `CommandStack`. Public mutating methods (`AddNode`, `SetProperty`, …) construct the command, push it on the stack, and apply it. Public read methods bypass the stack.

```csharp
session.Undo();   // pops and reverses
session.Redo();   // re-applies
session.History;  // IReadOnlyList<string> of descriptions
```

Why this is non-negotiable on day 1:

- **GUI editors live or die by Ctrl+Z.** Bolting it on after the fact means refactoring every mutating path to route through commands. Painful.
- **Agents need rollback.** An agent that scaffolds a complex scene and notices it went wrong should `Undo()` cleanly, not patch up halfway.
- **CLI gets it free** (`ke undo`, `ke redo`).

The cost is small if designed in: each mutating op already has a forward action; the inverse is usually trivial to express (`AddNode` ↔ `RemoveNode`, `SetProperty(k, v)` ↔ `SetProperty(k, oldValue)`).

## 6. Transactions

Group multiple commands into one undo step:

```csharp
using (var tx = session.BeginTransaction("Spawn enemy"))
{
    session.Scene.AddNode(parent, "Enemy", "Goblin");
    session.Scene.SetProperty(goblin, "Hp", 50);
    session.Scene.SetProperty(goblin, "Position", new Vector3(10, 0, 5));
    tx.Commit();
}
// One undo undoes all three.
```

Disposing without `Commit()` rolls back. Nested transactions flatten into the outermost.

Mandatory for agents — they make compound edits and must never leave a half-applied state if interrupted.

## 7. Change events

Frontends subscribe to mutations:

```csharp
session.Scene.OnNodeAdded     += (sender, e) => ...;
session.Scene.OnNodeRemoved   += (sender, e) => ...;
session.Scene.OnPropertyChanged += (sender, e) => ...;
session.Project.OnSettingsChanged += (sender, e) => ...;
```

Event args carry enough to update incrementally — full re-scan on every change is the wrong default.

For pull-based consumers (agents that poll between operations), `session.ChangeLog` returns a versioned log; the agent passes its last-seen version, gets deltas.

## 8. Authoring vs Runtime split

The lib is two sub-libs:

- **`KernelEngine.Editor.Authoring`** — operates on disk and in-memory models. No runtime engine, no GPU, no threads. Suitable for CI, scripts, agents, headless tooling. Most operations live here.
- **`KernelEngine.Editor.Runtime`** — operates on a live `Application` / `World`. Used by the eventual GUI editor's viewport and any "live edit" workflow. Wraps Authoring and additionally pushes changes into the running scene.

A frontend wires whichever it needs. CLI is Authoring-only by default. GUI uses both.

```
KernelEngine.Editor.Authoring
  ↑ (depends on)
KernelEngine.Editor.Runtime
  ↑
KernelEngine.Framework + Kernel
```

## 9. Session lifetime

```csharp
using var session = EditorSession.Open("path/to/project");
// ... operations ...
session.SaveAll();
```

`EditorSession` is the entry point. `IDisposable`. Owns:
- The active `Project` (one per session — open another → close this).
- The working-set of scenes.
- The `CommandStack`.
- The change event router.

Multi-session in a single process is allowed (e.g. comparing two projects) but they share no state.

## 10. Threading

The lib is **not thread-safe by default.** Operations on a session execute on the calling thread. Frontends that need background work (file watcher, build progress) marshal back to the session's owning thread for any mutation.

Rationale: the alternative is locks-everywhere or per-operation queue dispatch, both costly. The lib is fast enough to stay single-threaded for almost everything; long ops are async via `Task` and report progress, but their *commit* (writing back to the session) happens on the caller's thread after `await`.

GUI editors typically own the session on a "logic thread" separate from the render thread; CLI uses the main thread; agents own one per session. Trivially compatible.

## 11. What this lib is NOT

- **Not a UI library.** Zero references to ImGui/Avalonia/WPF/anything visual.
- **Not the runtime engine.** It depends on Framework, but is not a substitute for `Application.Run`. Game code does not consume Editor APIs.
- **Not where game logic lives.** Operations are project-level. Player movement code lives in `MyGame.Player : Node`, not in `Editor.GameLogic`.
- **Not a build system.** `Build.Compile` shells out to MSBuild / Ninja / shaderc. The lib coordinates; it does not reimplement.

## 12. Implementation order (when work begins)

1. `EditorSession.Open` + minimum Project.Create/Open/Save (one TOML file end-to-end).
2. Scene operations (`AddNode`, `SetProperty`, `Save`).
3. Commands + undo/redo on the operations from step 2.
4. Transactions + events.
5. Async ops (Asset.Import, Build.*) once a real long-running operation exists.
6. Resource operations as they become needed by examples.

Steps 1-4 are the "core". Anything else can wait.

## 13. Cross-references

- The vision this lib serves: [14 - Editor, CLI & Agent Layer](14%20-%20Editor%2C%20CLI%20%26%20Agent%20Layer.md).
- The files it reads/writes: [15 - Serialization & Project Files](15%20-%20Serialization%20%26%20Project%20Files.md).
- Configuration plumbing it leans on: [16 - Configuration Service](16%20-%20Configuration%20Service.md).
- Scene model it manipulates: [17 - Scene & Node Serialization](17%20-%20Scene%20%26%20Node%20Serialization.md).
- The CLI frontend that consumes this lib: [19 - CLI & Agent Surface](19%20-%20CLI%20%26%20Agent%20Surface.md).
