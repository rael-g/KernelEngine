# Framework

`KernelEngine.Framework` is the high-level, opinionated authoring API for game developers. It is **the author's ideal high-level layer, not a mandatory one** (Principle 9): a consumer can ignore it and use the kernel + plugins directly. It is built in a **different paradigm from the kernel** — an OOP scene tree (node→ECS) rather than raw ECS — chosen for ergonomics.

It references **only `KernelEngine.Kernel.Abstractions`** and obtains concretes through `IEngineHost`.

## The node→ECS paradigm

### Foundational decision: a Node is a view over the ECS ✅ (ratified)

Game devs author with typed **Nodes** only; the sparse-set ECS is an **invisible execution backend**.

- The ECS `*Component` structs and `componentId`s are an internal detail — the public framework surface is Nodes and their properties.
- A Node is a thin object-oriented *view* over an ECS entity. Node properties read/write ECS component data internally (e.g. `meshRenderer.Mesh = …` writes the mesh component behind the scenes).
- The hot paths (transform, rendering) iterate **packed ECS arrays** for cache efficiency; the nodes are just the authoring face.

**Why this is not slower than a pure-OOP engine** (e.g. Godot): Godot itself uses thin nodes over data-oriented "servers"; KernelEngine uses thin nodes over an ECS. The accepted trade: per-node script callbacks (`OnUpdate`) keep virtual-dispatch cost (same as Godot); ECS-pure engines (Bevy/DOTS) avoid that but lose OOP ergonomics. Deliberate choice: **ergonomics for gameplay code, ECS for system iteration.** Suited to typical games (hundreds–low thousands of active entities), not 10k+ scripted-node simulations.

### Composition model ✅ (ratified)

Gameplay is composed by **nesting child nodes** (Godot-style), not by an attached-component list. A `Player` has child nodes for rendering, physics, and even behavior. The dev *may* consolidate everything into a `Player` subclass instead — it's their choice, never forced.

**Gameplay state lives as plain managed fields on nodes — not ECS components.** A `Health` node is one cohesive class:

```csharp
class Health : Node
{
    public float Current = 100, Max = 100;
    public event Action? Died;                 // node event
    public void Damage(float amt) { Current = Math.Max(0, Current - amt); if (Current == 0) Died?.Invoke(); }
    protected override void OnUpdate(float dt) { /* regen, etc. */ }
}
```

No `HealthComponent`, no `HealthSystem` — that earlier model was rejected as incohesive for gameplay. Writing a custom ECS component + system remains an **advanced opt-in** for genuine mass simulation, not the default path.

## Current building blocks

### `Application` ✅
Orchestrates the 3-thread model (`ke.main`, `ke.render`, `ke.sim` — see [08 - Multithreading](08%20-%20Multithreading.md)). Exposes lifecycle hooks:

```csharp
app.OnReady  = (IResourceFactory resources) => { /* once, on ke.sim after render init */ };
app.OnUpdate = (ISceneWriter scene, IInputReader input) => { /* every sim frame */ };
app.Run(services);
```

> Threading rule: do **not** call the renderer from `OnReady`/`OnUpdate` (those run on ke.sim; GPU calls are ke.render-only). Use `IResourceFactory` (marshaled) instead.

### `Scene` ✅
Façade over the world: `AddNode(name, parent?)`, `AddNode<T>(node, name, parent?)`, `DestroyNode(node)`, root access.

### `Node` ✅
ECS-backed, subclassable. Identity (`Entity`, `Name`), `LocalTransform`, `WorldMatrix`, hierarchy (`Parent`/`FirstChild`/`NextSibling`), and `OnStart()`/`OnUpdate(float)` virtuals dispatched via a script component + the native script system. A static `entity → Node` registry bridges the unmanaged script callbacks back to managed instances.

### Built-in node types ✅
`MeshNode`, `CameraNode`, `LightNode`, `PointLightNode`, `SpotLightNode`, `SkyboxNode`. These are the "the node type *is* the component" model — each maps to ECS data consumed by a render system.

### Render systems (pure-managed C#) ✅
`MeshRenderSystem`, `CameraRenderSystem`, `LightRenderSystem`, `ShadowRenderSystem`, `SkyboxRenderSystem`. They query the ECS (read-only, via `IEcsRegistry` spans) and record into the frame packet via the safe `IFramePacket` API. **They are pure-managed C# in the framework** — an earlier C++/native version was migrated back to C# (see [07 - Graphics & Rendering](07%20-%20Graphics%20%26%20Rendering.md) and the backlog).

## The High-Level API initiative (Framework, planned) 📋

The north star is that game code touches **only** Nodes and high-level types — never a handle, native pointer, component ID, or backend type. Today it still leaks into building blocks in a few places (measured in examples 06/12/13):

| Leak today | Planned framework abstraction |
|---|---|
| `IResourceFactory` + raw handles + `Vertex[]` (in `OnReady`) | High-level `Material`, `Mesh` (+ primitive factory), `Texture`, `Assets`/`AssetManager` |
| `ISceneWriter` post-fx/ambient/clear (per-frame in `OnUpdate`) | `Scene.Environment` + `Scene.PostProcessing` (persistent config) |
| `IInputReader.IsKeyDown(87)` magic keycodes | `Key`/`MouseButton` enums, input action/axis mapping, `Input` façade |
| `IWorld.ActiveCamera = node.Entity` (raw entity IDs) | `scene.MainCamera = cameraNode`, hidden component IDs |
| manual GPU-upload loop after `IAssetLoader` | `scene.Add(model)` / `model.Instantiate(scene)` |

Planned Godot-/Unity-inspired enrichments (naming uses .NET/Unity terms, never Godot's):
- **Scene as the universal reuse unit**: everything is a `Scene` (a node subtree); reuse = `scene.Instantiate()`. No separate "Prefab" type. Serialized form (deferred) is a `SceneAsset`.
- **`SceneManager`**: active scene, scene switching, global pause.
- **Tags** (== Godot groups): `node.AddTag("enemy")`, `scene.FindWithTag(...)`.
- **Node events**: decoupled events via idiomatic C# `event`/delegates (fills the Observer gap from the removed MessagePipe).
- **Richer lifecycle**: `OnFixedUpdate(dt)`, `OnEnable`/`OnDisable`/`OnDestroy`, `OnEnterTree`/`OnExitTree`; event-based input (`OnInput`).
- **`Time`** service, reusable **camera controllers** (orbit/fly/fps).
- Node-type rename to Unity/.NET convention (`MeshNode` → `MeshRenderer`, `CameraNode` → `Camera`, lights → `DirectionalLight`/`PointLight`/`SpotLight`).

The full, ordered card list lives in [`Kanban.md`](../Kanban.md) under **Tier 2 — Framework High-Level API**. Each card's acceptance gate: the target leak no longer appears in `examples/csharp/`. This reference describes the *intent*; the Kanban tracks live status.

## Game developer entry point (today)

```csharp
var services = new ServiceCollection()
    .AddKernel().AddLogger().AddConsoleSink().AddInput()
    .AddGlfwWindow(1280, 720, "Title")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();
app.OnReady  = resources => { var mesh = resources.CreateMesh(verts, indices); /* … */ };
app.OnUpdate = (scene, input) => { scene.ClearColor(0.1f, 0.1f, 0.1f, 1f); if (input.IsKeyDown(87)) { } };
app.Run(services);
```

As the High-Level API initiative lands, `OnReady`/`OnUpdate` shrink toward node composition + scene config, and the raw building-block calls above disappear from game code.
