# C# Layers

The managed side is a layered stack designed so that **game code depends only on abstractions**, never on native pointers or backend types. This is a hexagonal / ports-and-adapters arrangement.

## Projects (flat under `src/csharp/`)

| Project | Role |
|---|---|
| `KernelEngine.Kernel.Abstractions` | Pure contracts + POCOs (the "ports"). Zero `unsafe`. |
| `KernelEngine.Kernel` | Concrete wrappers owning native pointers (the kernel "adapters"). |
| `KernelEngine.Framework` | High-level node→ECS API (see [06](06%20-%20Framework.md)). |
| `KernelEngine.Render.Bgfx` | Renderer plugin wrapper + `AddBgfxRenderer()`. |
| `KernelEngine.Window.Glfw` | Window plugin wrapper + `AddGlfwWindow()`. |
| `KernelEngine.Asset.Assimp` | Asset loader plugin wrapper + `AddAssimpAssetLoader()`. |
| `KernelEngine.TaskScheduler.Enki` | Task scheduler plugin wrapper. |
| `KernelEngine.DevPlatform.Win32` | Dev-platform plugin wrapper. |
| `KernelEngine.Logging.Serilog` | Serilog logger sink wrapper. |

Native P/Invoke bindings are **not** separate projects — they live as `Native/Generated/` subfolders inside the relevant wrapper project (e.g. `KernelEngine.Kernel/Native/Generated/`), under a `*.Native` namespace.

## Layer 3 — Native bindings (generated)

ClangSharp-generated P/Invoke over the C ABI. Generated from `.rsp` files via `scripts/generate_bindings.py`; **never hand-edited**. Each `.rsp` controls which headers are processed and which types are excluded.

> **Gotcha**: ClangSharp sometimes emits nested `partial struct` forward-declaration stubs that shadow the outer type, breaking function-pointer resolution. The fix is to remove the nested stub. (Documented historically for `ke_ecs_registry`.)

## Layer 4a — Abstractions

`KernelEngine.Kernel.Abstractions` is the **building-blocks API**: the contracts a renderer/window/world satisfy, plus the pure value types they exchange. **No `unsafe`, no native pointer ever appears in a public interface.**

Contracts (interfaces): `IAllocator` (+ arena/proxy/malloc variants), `ILogger`, `ILoggerSink`, `IWindow`, `IRenderer`, `IDevPlatform`, `IInput`, `IInputReader`, `IInputBuffer`, `ITaskScheduler`, `IFrameSync`, `IFramePacket`, `IEcsRegistry`, `IWorld`, `ISystem`, `ISceneWriter`, `IResourceFactory`, `IResourceCommandQueue`, `IKernelThread`, `IEngineHost`, `IAssetLoader` / `IModel` / `IModelMesh` / `IModelMaterial` / `IModelTexture`.

Value types / POCOs: `Vertex`, `Transform`, `TransformComponent`, `HierarchyComponent`, `NameComponent`, light records, typed handles (`MeshHandle`, `TextureHandle`, `MaterialHandle`, `ShadowMapHandle` — all using `uint.MaxValue` as the `None` sentinel; handle `0` is the built-in white texture), `Result` / `KernelResult` / `KernelException`, `LogLevel`, `ComponentAccess`, `RequiresThreadAttribute`.

> 📋 **Decided (Kanban [B5.7])**: Abstractions should be a cohesive ~0.9:1 managed mirror of the C kernel. The contracts that encode the **Framework's 3-thread policy** — `ISceneWriter`, `IResourceFactory`, `IResourceCommandQueue`, `IInputBuffer` — will **move out of Abstractions into `KernelEngine.Framework`** (along with their concretes). A framework with a different threading model should reuse Abstractions without inheriting this policy. The mirror stays span-reshaped for C# safety; an `IShaderCompiler` may be added to complete it.

### `IEcsRegistry` — safe ECS access
The registry interface exposes component storage as `Span<T>` / `ReadOnlySpan<T>` rather than raw pointers, so consumers manipulate ECS data safely without `unsafe`. Queries return packed spans.

### `IEngineHost` — factory façade 🚧 (being removed)
Because the framework cannot reference concrete types, it currently obtains them through `IEngineHost`: `CreateWorld(...)`, `CreateFrameSync(...)`, `CreateProxyAllocator(...)`, `CreateThread(...)`, `SetCurrentThreadName(...)`, `CreateInputBuffer()`, `CreateResourceCommandQueue()`, `CreateSceneWriter(packet)`. The concrete `EngineHost` (in `KernelEngine.Kernel`) returns concrete implementations typed as their interfaces.

> 📋 **Decided (Kanban [B5.7])**: `IEngineHost` is a service-locator / god-factory anti-pattern and will be **removed** in favour of DI. No-param creations become DI registrations (`AddKernel()` registers `IWorld`/`IFrameSync`); runtime-parameterized ones become small typed factories (e.g. `IThreadFactory`); the policy creations disappear because their concretes move to the Framework (next note).

## Layer 4a — Kernel wrappers

`KernelEngine.Kernel` holds the concrete wrappers (`Allocator`, `Logger`, `Renderer`, `Window`, `World`, `Input`, `TaskScheduler`, `FramePacket`, `FrameSync`, `InputBuffer`, `ResourceCommandQueue`, `EngineHost`, …). Each:

- Owns its native pointer **`private`** — no `public`, no `internal` leakage of `ke_X*`.
- Implements the corresponding Abstractions interface.
- Exposes only managed methods. Every operation a consumer needs is a managed method on the wrapper; nobody reaches in for the pointer.

This full encapsulation is the result of the B5.1 hardening (see [12 - Architecture Backlog & Decisions](12%20-%20Architecture%20Backlog%20%26%20Decisions.md)). `InternalsVisibleTo` is restricted to test assemblies.

Covariant returns are handled via explicit interface implementation where a concrete wrapper returns a concrete type but the interface wants the abstraction (e.g. `FrameSync.BeginRead()` returns `FramePacket`; `IFrameSync.BeginRead()` returns `IFramePacket`).

## Plugin wrapper assemblies

Each plugin wrapper (`Render.Bgfx`, `Window.Glfw`, `Asset.Assimp`, …) references the concrete `KernelEngine.Kernel` (they are engine-internal adapters) and provides a DI extension that constructs the native plugin and registers it **behind an Abstractions interface**:

```csharp
services.AddSingleton<IAssetLoader>(sp => { /* create native, wrap, return */ });
```

Game code calls `.AddAssimpAssetLoader()` purely for the side effect of registration; it then resolves `IAssetLoader`, never the concrete loader. Plugin concrete types are `internal` where possible, so the boundary is enforced by the compiler, not just discipline.

## Dependency rules (enforced)

- `Framework` → references **only** `Abstractions`.
- Game code → `Framework` + `Abstractions`; plugin assemblies only for `.AddXxx()` extensions.
- Plugin wrappers → `Kernel` (allowed; they are adapters).
- No public/`internal` `ke_X* Native` anywhere; no `unsafe` in game code.

## Async & tasks

`KernelTask` / `KernelTask<T>` wrap `Task`/`Task<T>` with `await` support, used for work dispatched to the native scheduler. The asset loader's async API and the `IResourceFactory` async extensions build on standard `Task<T>`. GPU resource creation from the sim thread is marshaled to the render thread via `IResourceCommandQueue` (see [08 - Multithreading](08%20-%20Multithreading.md)).
