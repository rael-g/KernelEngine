# Framework Architecture V2

**Branch**: `feat/framework-v2` (not started — work begins after `feat/runtime-v2` merges to `main`).

**Status**: Design locked and prioritized. No implementation exists yet. Every section below is confirmed scope for this branch; nothing here enters `feat/runtime-v2`.

**Companion docs**:
- [`RuntimeArchitectureV2.md`](RuntimeArchitectureV2.md) — runtime contract (scheduler + ECS + V1 merge arc). After `feat/runtime-v2` merges, that doc becomes historical reference; this doc takes over as the active design source.
- [`RenderArchitectureV2.md`](RenderArchitectureV2.md) — future renderer (`ke_gpu_device` WebGPU-style ABI). §6 of this doc (render pipelining) is blocked on Render V2.
- [`docs/Kanban.md`](Kanban.md) — active work cards.

**Audience**: Engine maintainer + Framework contributors.

---

## 1. What this document covers

Seven work categories for branch `feat/framework-v2`. Recommended execution order:

1. **Example migrations** — port existing examples to the new Runtime model (R3/R4/R6/R7 from the original migration plan).
2. **`ke_font_handle`** — promote font to a first-class resource handle (removes the current raw pointer).
3. **Kanban A16** — owner/borrow split in `ke_ecs` to make the lifetime contract physical in the C type system.
4. **Legacy framework audit** — read `KernelEngine.Framework.Legacy`, gap analysis vs current Toolkit, decide per gap.
5. **C# ergonomics layer (source gen)** — source generator, `ref struct View` as the full access funnel, NodeBehavior, Roslyn analyzer (lifted from `RuntimeArchitectureV2.md` §3.5 + §15).
6. **Node hierarchy redesign** — Node3D / Node2D / Canvas / Control split (lifted from `RuntimeArchitectureV2.md` §17.6.4 decision #10).
7. **Render pipelining** — component snapshot for sim N+1 ∥ render N (lifted from `RuntimeArchitectureV2.md` §16). **Blocked on Render V2.**

> Sections below are numbered in document order; the recommended execution order is listed above.

---

## 2. Example migrations — R3/R4/R6/R7

Phases R3–R7 from the original plan (`RuntimeArchitectureV2.md` §14) were never implemented because the §17 arc took a different approach — the G-phase focused on architecture, not on example migration. After `feat/runtime-v2` merges, examples 01–16 still run via the legacy `Application.cs`. This branch completes the migration.

### 2.1 R3 — `01_runtime_clear_color` aligned with the final G-phase shape

`01_runtime_clear_color` already drives `ke_runtime` directly (it was the R2.5 validation example). Review it against the final G-phase shape (`IRuntimeModule`, `World`, `SceneRenderModule`, etc.) and fix any drift. `00_runtime_minimal` also covers this slot.

**Acceptance**: `dotnet run` on `01_runtime_clear_color` shows the window with no `Application.cs` in the call stack.

### 2.2 R4 — `RenderModule` wrapping the current renderer

Today, examples that need rendering construct `BgfxRenderModule` directly. R4 formalizes this as a clean `IRuntimeModule` that:
- Registers `MeshRenderSystem`, `CameraRenderSystem`, `LightRenderSystem`, `SkyboxRenderSystem`, `ShadowRenderSystem` as Extract-phase systems.
- Does not assume `Application.cs` in the host.
- Composes like any other module: `services.Add<IRuntimeModule, RenderModule>()`.

**Acceptance**: `02_mesh_renderer` + `03_lighting` run via `RenderModule` with no `Application.cs`.

### 2.3 R6 — Examples 02–15 migrated incrementally

Each example is ported: replace `Application.cs` + `Tree` with `IRuntimeModule` + `World` + `NodeWorld`. Order: smallest dependency cone first (01 → 02 → 03 → ... → 15 → pong_legacy).

**Acceptance per example**: visual output identical to pre-migration; `Application.cs` not in the call stack.

### 2.4 R7 — `Application.cs` deleted

After all examples are migrated (R6), `KernelEngine.Framework.Application` is deleted. The class exists only as a compatibility bridge; no external consumer depends on it.

**Acceptance**: `grep -r "Application" src/csharp/ examples/` returns zero relevant hits. Build green.

---

## 3. `ke_font_handle` — font as a first-class resource handle

`Font` currently exists as managed C# holding a `ke_font_data*` raw pointer stored on a `Label` instance. This:
- Leaks an unmanaged pointer outside the ECS (instance field on a Node, not a component).
- Prevents fonts from being managed by `ke_resource_cache` (no typed handle).
- Blocks implementing `Label` as a `Control` in §7 (Node hierarchy).

### 3.1 The shape

```c
// In kernel/text/font.h (ke_font_loader vtable already exists)
typedef uint32_t ke_font_handle;
#define KE_FONT_HANDLE_INVALID 0

// ke_render gains:
ke_font_handle (*upload_font)(ke_render *self, const ke_font_data *data);
void           (*destroy_font)(ke_render *self, ke_font_handle handle);
```

`ke_resource_cache` manages lifetime (refcount + dedup by path + size). The C# `FontLoader` wrapper holds `ke_font_handle` as `uint` — precedent: `MeshHandle`, `MaterialHandle`.

### 3.2 Cascade changes

- `ke_label_component` (when created in §7) uses `ke_font_handle`, not `ke_font_data*`.
- C# `Font` wrapper becomes `struct FontHandle { public uint Handle; }` — no longer a class with a finalizer.
- `ResolvedFontData` and `INativeFontLoader` return `ke_font_handle` after upload to the renderer.
- Managed `Label` (current) keeps working via `ke_font_handle` until §7 lands.

**Estimated**: 1 session.

---

## 4. Kanban A16 — owner/borrow split in `ke_ecs`

**Context** (from `RuntimeArchitectureV2.md` §17.6.2 decision #9): the "whoever creates, owns" rule is a documented convention, not physical in the C type system. `ke_ecs*` is the same type whether it is the owner or a borrow. This causes ambiguity and already led to one design reversal (world ownership model).

### 4.1 Proposed shape

```c
// ke_ecs is the owner handle — returned by ke_ecs_flecs_create(), passed to ke_ecs_flecs_destroy().
typedef struct ke_ecs ke_ecs;

// ke_ecs_view is the borrow handle — passed to consumers (ke_runtime, ke_scene_tree, etc.)
// that use the storage but are not responsible for its lifetime.
typedef struct ke_ecs_view ke_ecs_view;

// Obtain a view from an owner:
ke_ecs_view *ke_ecs_get_view(ke_ecs *self);

// All consumer vtables use ke_ecs_view* instead of ke_ecs*:
ke_result ke_runtime_create(ke_allocator*, ke_ecs_view*, ke_task_scheduler*, ...);
ke_result ke_scene_tree_create(ke_allocator*, ke_ecs_view*, ...);
```

In C++ or Rust this would be `unique_ptr` vs reference; in C it is a naming convention made physical.

### 4.2 Impact

- Every call site that passes `ke_ecs*` to runtime / scene_tree / world migrates to `ke_ecs_view*`.
- ClangSharp regen required for affected bindings.
- Existing integration tests stay green — the change is type-level, not behavioral.

**Estimated**: 1-2 sessions (signature refactor + regen).

---

## 5. C# ergonomics layer — source generator + script safety model

### 5.1 What exists today (V1 baseline)

`Node` subclasses override `OnUpdate(in View view)`. The `View` is a manually-written struct passed per-frame. The `NodeBehavior` base class does not exist yet — effects with state are written as full `Node` subclasses. The Roslyn analyzer and source generator do not exist.

Node type registration for scene files is manual: `services.AddNodeType<Wall>("Pong.Wall")`. Source gen will eliminate this ceremony.

### 5.2 Phase 1 — source gen for node type registration

**Goal**: eliminate `.AddNodeType<T>()` from game code. The dev marks the class; the engine discovers it.

**Mechanism**: Roslyn `IIncrementalGenerator` in a new project `src/csharp/KernelEngine.SourceGenerators`. Finds all classes annotated with `[SceneNode]` (or, as an escape hatch, all `Node` subclasses in the compilation). Generates:

```csharp
// Auto-generated by KernelEngine.SourceGenerators
internal static class KernelEngineNodeRegistration
{
    public static IServiceCollection AddSceneNodes(this IServiceCollection services)
    {
        services.AddNodeType<Wall>("Pong.Wall");
        services.AddNodeType<Paddle>("Pong.Paddle");
        // ... all [SceneNode]-annotated types in the compilation
        return services;
    }
}
```

Game `Program.cs` calls `services.AddSceneNodes()` — one line, no manual list.

**[SceneNode] attribute**:

```csharp
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class SceneNodeAttribute : Attribute
{
    /// <summary>Scene-file type name. Defaults to <c>Namespace.ClassName</c>.</summary>
    public string? Name { get; }
    public SceneNodeAttribute(string? name = null) { Name = name; }
}
```

Engine built-in types (Camera, MeshRenderer, DirectionalLight, etc.) are decorated with `[SceneNode]` in Toolkit — the generator discovers them automatically when Toolkit is in the compilation. No separate "register engine nodes" call.

**Source gen project setup**: referenced from game projects as an analyzer:
```xml
<ProjectReference Include="../../engine/KernelEngine.SourceGenerators.csproj"
                  OutputItemType="Analyzer"
                  ReferenceOutputAssembly="false" />
```

**Estimated**: 1 session (incremental generator is simple; logic is a type scan + string emit).

### 5.3 Phase 2 — `ref struct View` funnel

All component / resource access in `OnUpdate` and `NodeBehavior.Run` goes through a `ref struct View` parameter. Because `ref struct` cannot escape the stack (no boxing, no lambda capture, no field storage), the C# compiler enforces that component access handles never reach code the analyzer hasn't seen. No discipline required — the build fails.

```csharp
public class Paddle : Node {
    public override void OnUpdate(in View view) {
        view.Velocity.X = view.Input.GetAxis("Move") * 5f;
        view.Transform.Position.Y += view.Velocity.Y * view.DeltaTime;
    }
}
```

The `View` is **generated per class** by the source generator — it exposes only the components/resources declared by that class (via `[ComponentAccess<T>]` attributes or inferred from the method body by the analyzer). Different `Node` subclasses get different View shapes; calling `view.SomeComponentNotDeclared` is a compile error on the generated View type.

`View` wraps `ke_system_ctx*` underneath. Every `view.Transform.Position = ...` lowers to `ke_system_ctx_get_mut(ctx, CID_TRANSFORM, entity)`. The ref struct adds compile-time enforcement; the door still checks in debug builds.

**Estimated**: 2-3 sessions (View codegen + integration with scheduler + examples ported).

### 5.4 Phase 3 — NodeBehavior pattern

`NodeBehavior` is the single syntactic surface for "behavior with state that ticks". Codegen transforms it into component + system:

```csharp
public partial class JumpEffect : NodeBehavior {
    public float TimeLeft;
    public Vector3 Velocity;

    public void Run(in View view, float dt) {
        TimeLeft -= dt;
        view.Transform.Position += Velocity * dt;
        if (TimeLeft <= 0) Finish();
    }
}

// Usage in any Node's OnUpdate:
view.Attach(new JumpEffect { TimeLeft = 0.3f, Velocity = new(0, 5, 0) });
```

Codegen emits:
- `JumpEffect_Data` struct — POD holding the public fields
- `JumpEffect_Tick` system — queries all entities with the component, calls `Run`
- `View.Attach<JumpEffect>` / `View.Detach<JumpEffect>` extensions
- R/W metadata for the system, inferred from `Run`'s body

Framework ships: `NodeBehavior` base class + three canonical examples (`Timer`, `Tween`, `Delay`). Community extends the pattern endlessly without touching framework code.

**Estimated**: 3-4 sessions (codegen is the most complex part of the ergonomics layer).

### 5.5 Phase 4 — Node fields as components

Every declared non-`[Local]` field on a `Node` or `NodeBehavior` subclass becomes part of an auto-generated `<ClassName>_Data` component. Codegen rewrites field accesses to route through the View. The dev's experience is Unity-like (declare fields, use them as fields); the runtime sees ECS data.

```csharp
public partial class Paddle : Node {
    public float Speed = 5f;
    public Color Color = Color.Red;
    [Local] private List<EnemyTarget> _nearbyEnemies; // stays on heap, disables parallelism

    public override void OnUpdate(in View view) {
        view.Transform.Position.X += Speed * view.DeltaTime;
        view.Material.Tint = Color;
    }
}
```

Consequences that ride for free: uniform serialization (save/load = serialize the world), hot reload (state in ECS, not C# heap), networking (replicate `Paddle_Data`), determinism (no hidden heap state), editor inspection (reads `Paddle_Data` directly).

Non-POD field without `[Local]` → build error `KE0042`.

**Estimated**: 3-4 sessions.

### 5.6 Phase 5 — Roslyn analyzer + AOT enforcement

Three enforcement layers:

1. **Roslyn analyzer** (IDE-time): reads project's `<PublishAot>` MSBuild property. If `PublishAot != "true"`, violations of banned APIs (§15.2: reflection, unsafe, DllImport, dynamic) emit **warning**. If `PublishAot == "true"`, same violations emit **error**. Escape hatch: `<KernelEngineAllowJit>true</KernelEngineAllowJit>` suppresses warnings in JIT mode.

2. **MSBuild target** (build-time): in Release configuration without `PublishAot`, build fails:
   ```xml
   <Target Name="_KernelEngineEnforceAot" BeforeTargets="Build"
           Condition="'$(Configuration)' == 'Release'">
     <Error Condition="'$(PublishAot)' != 'true' AND '$(KernelEngineAllowJit)' != 'true'"
            Text="KernelEngine release builds require &lt;PublishAot&gt;true&lt;/PublishAot&gt;." />
   </Target>
   ```

3. **Runtime check** (startup): `RuntimeFeature.IsDynamicCodeSupported == true` in release config → `EngineConfigurationException`.

**[System] source-gen path for engine devs** (§3.5):

```csharp
[System(Phase.Update)]
static void PaddleSystem(
    Query<Mut<Transform>, With<Paddle>> paddles,
    Res<Time> time,
    Res<InputState> input)
{
    foreach (var (transform, _) in paddles)
        if (input.Value.IsPressed(MoveAction.Up))
            transform.Value.Position.Y += 5f * time.Value.dt;
}
```

The generator reads parameter types, emits `ke_runtime_system_params` + the typed wrapper callback. The companion analyzer enforces: mutating a `Query<T>` (non-`Mut`) parameter → red squiggle. Accessing undeclared resource → red squiggle.

**Estimated**: 4-5 sessions (most complex piece; 6-10 if hardening for production).

---

## 6. Render pipelining — component snapshot

> This section is **blocked on Render V2**. Read `RenderArchitectureV2.md` first.
> Full design rationale in `RuntimeArchitectureV2.md` §16 (V1 history).

### 6.0 Dependency: Render V2 must land first

The V1 renderer (`BgfxRenderModule`) uses `IFrameContributor` + `IFramePacket` + `FrameSync` as a temporary adapter layer. Contributors read ECS and write into a double-buffered packet; the render worker consumes the packet via `renderer.SubmitPacket`. The frame_packet exists precisely because the native renderer's per-call setters are stubs (documented as tech debt in `BgfxRenderModule.cs`).

In **Render V2** (`RenderArchitectureV2.md`), the renderer registers itself as a ke_runtime system in the Extract/Render phase and reads ECS **directly** via `ke_system_ctx` — like any other system. When that happens:
- `IFrameContributor` and all contributor classes are deleted
- `IFramePacket`, `FrameSync`, `frame_packet.h`, `ke_frame_sync` are deleted
- `BgfxRenderModule` collapses to a thin module that initializes bgfx and registers the render system

Only after Render V2 registers render-phase systems with formal `access_list` declarations does the pipelining design below become implementable. The scheduler can only infer which components to double-buffer once it knows which systems read them in the render phase.

**Implementation order**: Render V2 → then pipelining.

### 6.1 The pipelining design (contingent on Render V2)

**Problem**: with Render V2, sim and render become two properly-declared ke_runtime phases. They still run serially by default. On heavy scenes, ~15-30% CPU budget is unused vs an engine that runs sim N+1 in parallel with render N.

**Chosen approach**: Option B — component snapshot via `ke_ecs` extension. Components accessed by render-phase systems get a back buffer in the storage layer (`KE_COMPONENT_DOUBLE_BUFFERED`). Phase boundaries swap buffers atomically. Sim writes live; render reads snapshot. Single world preserved.

**Inference, not manual marking**: at startup, the scheduler scans every system with render-phase affinity and marks their declared component ids as double-buffered. Game code never calls `KE_COMPONENT_DOUBLE_BUFFERED` directly. Escape hatches: `[NoDoubleBuffer]` and `[ForceDoubleBuffer]` exist but are not the normal path.

### 6.2 ke_ecs contract addition (post Render V2)

```c
typedef enum ke_component_flags {
    KE_COMPONENT_NONE            = 0,
    KE_COMPONENT_DOUBLE_BUFFERED = 1 << 0,
} ke_component_flags;

ke_component_id (*component_register_v3)(struct ke_ecs *self,
                                          const char        *name,
                                          size_t             element_size,
                                          ke_component_flags flags);

void (*swap_snapshots)(struct ke_ecs *self);
```

The flecs impl: each double-buffered component becomes two internal flecs components (`X_live` + `X_snap`). Swap rotates an index. R/W metadata in `ke_runtime_system_params.access_list` becomes phase-aware.

### 6.3 Implementation phases (post Render V2)

- **R6** — `ke_ecs` contract extension + flecs impl + inference algorithm in scheduler
- **R7** — validate parity; enable pipelining flag

**Trigger**: profiler-driven, not speculative. Don't implement until frame budget analysis shows the gap.

**Estimated**: 4-5 sessions total (R6: 2-3, R7: 1-2).

---

## 7. Node hierarchy redesign — Node3D / Node2D / Canvas / Control

> Locked design from `RuntimeArchitectureV2.md` §17.6.4 decision #10.

### 7.1 The split

| Class | Transform | Use |
|---|---|---|
| `Node3D` | `ke_transform_component` (3D world space) | 3D objects, meshes, lights, cameras |
| `Node2D` | `ke_transform2d_component` (xy + rot + scale, pixel/unit space) | Pure-2D pixel-space games |
| `Canvas` | None | UI boundary — breaks transform inheritance chain |
| `Control` | `ke_ui_anchor_component` | Anchored UI elements |

**Rules**:
- `Node3D` inherits transform only from `Node3D` parents.
- `Node2D` inherits transform only from `Node2D` parents.
- `Canvas` children can only be `Control` (scene_loader validates at load time).
- `"Node3D → Canvas → Node3D"` is invalid hierarchy.
- **2.5D / Octopath / billboards use `Node3D` + billboard rendering flag** — 2.5D is 3D world space with sprite art, not `Node2D`.

**Current `Node`**: becomes `Node3D`. All existing examples that use `Node` continue to work with a type alias until the rename is complete.

### 7.2 What this unlocks

- `ke_transform2d_component` in `components.h` (currently missing).
- `ke_ui_anchor_component` in `components.h` (currently missing).
- `Label` promoted from managed C# hack to a proper `Control` subclass with native `ke_font_handle`.
- `ke_font_handle` as a first-class resource handle (uint32, like `ke_mesh_handle`) — currently `ke_font_data*` raw pointer in managed code.

### 7.3 Estimated

2-3 sessions (C components + C# hierarchy + scene_loader validation + example updates).

---

## 8. Legacy framework audit

`KernelEngine.Framework.Legacy` has been running in production for the lifetime of the Pong prototype. It contains hard-won lessons. Before it is deleted from the repo, every file must be read and a conscious decision made for each capability.

**Decision categories**:
- **Port to Toolkit** — capability missing in current Toolkit; bring it over now.
- **Defer to native** — capability that should be in a native plugin (`src/c/framework/`); design the vtable extension and track in Kanban.
- **Covered** — already exists in Toolkit/Framework; confirm behavior parity.
- **Discard** — design was wrong or superseded; delete without replacement.

### 8.1 Audit checklist

| File | Category | Notes |
|---|---|---|
| `Application.cs` | Discard | Replaced by `IRuntimeModule` host pattern |
| `Scene/NodeTypeResolver.cs` | Port to Toolkit | Reflection-based scan; will be replaced by source gen in §2.2; port now so `.AddNodeType<T>()` manual registration is eliminated |
| `Scene/SceneLoader.cs` | Covered | Replaced by `NativeSceneLoader` wrapping `ke_scene_loader*` |
| `Scene/Tree.cs` | Covered (→ SceneTree) | Replaced by `SceneTree` |
| `Scene/Scene.cs` | Review | Check if subscene / nested scene loading is covered by `ke_scene_loader` TOML grammar |
| `Scene/TreeExtensions.cs` | Review | Utilities on top of Tree — check if any are missing from SceneTree |
| `Scene/Node.cs` | Covered | Replaced by Toolkit `Node` |
| `Resources/ResourceManager.cs` | Review | Material/texture creation helpers + async patterns; check parity with `ModelExtensions` |
| `Resources/Assets.cs` | Review | Asset path resolution; check against `NativeAssetResolver` |
| `Input/InputActionMap.cs` | Covered | Replaced by `NativeInputActions` wrapper |
| `Input/InputActionsServiceExtensions.cs` | Review | DI extension shape — check against current `InputActionsServiceCollectionExtensions` |
| `Input/GameActionsAttribute.cs` | Review | Attribute-driven input action registration — potential source gen candidate |
| `Input/InputActions.cs` | Covered | Replaced by `NativeInputActions` |
| `Physics/Physics2DSystem.cs` | Review | Physics integration — check against `16_physics_test` |
| `Physics/Physics2DContext.cs` | Review | Physics context shape — check against Box2D plugin |
| `Physics/CollisionShape2D.cs` | Review | May be missing from current Toolkit |
| `Physics/CollisionBody2D.cs` | Review | May be missing from current Toolkit |
| `Nodes/Sprite2D.cs` | Review | 2D sprite rendering — blocked on Node2D hierarchy (§4) |
| `Nodes/Camera.cs` | Covered | Replaced by Toolkit `Camera` |
| `Text/Label.cs` | Covered (deliberate debt) | Managed Label stays until Canvas/Control hierarchy lands |
| `Text/LabelRenderSystem.cs` | Covered | Replaced by `LabelContributor` |
| `Audio/AudioPlayer.cs` | Review | Check parity with current audio integration |
| `Audio/AudioServiceExtensions.cs` | Review | Check against current DI extensions |

**Output of audit**: one Kanban card per "Defer to native" decision (vtable spec + impl estimate). One Toolkit PR per "Port to Toolkit" item. One comment per "Covered" item confirming behavior parity test exists.

### 8.2 Priority order

1. `NodeTypeResolver` — unblocks eliminating `.AddNodeType<T>()` manual registration immediately (no source gen needed).
2. `Scene/Scene.cs` + `TreeExtensions.cs` — likely small gaps in SceneTree.
3. Physics nodes — Pong + example 16 depend on them.
4. `GameActionsAttribute` — input action discovery pattern worth understanding before source gen is designed.
5. Everything else — lower urgency, do before legacy is deleted from repo.

---

## 9. Open questions

1. **`ke_font_handle`** — define the handle + resource cache registration before or after the Node3D/2D split? The split is a prerequisite for Label moving to Control, but the handle is useful independently (font upload for Label already happens without a proper handle).

2. **`IInputActionReader<TEnum>` in legacy** — Pong's `Paddle` takes `IInputActionReader<PongAction>` as a DI-injected constructor parameter. Current Toolkit `InputActionMap` wraps `NativeInputActions` but the generic `IInputActionReader<TEnum>` interface may be missing. Verify parity.

3. **Subscene / nested scene loading** — `SceneLoader.cs` (legacy) has `scene = "res://subscene.scene"` support. Does `ke_scene_loader` (native) support the same nested-scene syntax? Check scene_loader.c.

4. **`[GameActions]` attribute** — legacy has `GameActionsAttribute` for marking an enum as the game's action set. Current pattern uses `AddInputActions<PongAction>()` (explicit generic call). Is the attribute approach better for the source gen era?

5. **Variadic queries** — `Query<T1, T2, T3, T4>` arity is unbounded. Approaches: (a) generate T1..T16 overloads; (b) use C# `ITuple` + boxing (slow); (c) emit per-call specialized types. Lock during §2.3 implementation.

---

## 10. Non-goals for this arc

- Hot module reload — V3.
- Distributed / networked runtime — out of scope.
- Lua / Python bindings — the C ABI contract already supports them; managed sugar is C# only.
- Runtime-swappable ECS mid-game — locked at startup per V1 doctrine.
