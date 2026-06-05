# ECS-Pure Nodes — Refactor Plan

**Branch**: `refactor/ecs-pure-nodes`
**Status**: Planning. Not started.
**Estimate**: 4–6 sessions.

---

## 1. Problem statement

The `feat/tier-s-contracts` branch surfaced two compounding pains while porting
Pong to Lua:

1. **Node-type registration is verbose per language.** Each `ke_node_type`
   carries two callbacks (`create`, `set_property`). Bindings end up writing
   ~45 lines of manual variant decoding per node type. C# hides this in 310
   lines of reflection (`NodeTypeRegistrar.cs`), but the same cost would
   re-emerge the day C# stops using reflection. Lua paid the bill in full —
   `examples/lua/pong/main.lua` is dominated by three of those blocks.

2. **The "node type" concept duplicates information already in ECS.** A
   "MeshNode type" really means "an entity with `MeshComponent` plus a Transform".
   Today this mapping is hard-coded in the type's callbacks instead of being
   read from the component metadata the ECS already maintains.

Hand-wavingly: today we treat the scene file as a list of *typed nodes*; we
want it to be a list of *entities with components*. The current Node-class
ergonomics (Godot-style `class MeshNode : Node`) stays — it becomes a thin
C# sugar layer that wraps "an entity with a fixed set of components".

This refactor is the precondition for porting Pong to Lua without sugar at a
sane line count, and it deletes ~300 lines of C# reflection plumbing.

---

## 2. Before / After

### Scene file

```toml
# BEFORE — type-driven
[[node]]
name = "Cube"
type = "Mesh"                        # ← whole concept goes away
[node.transform]
rotation_euler = [20, 35, 0]
[node.properties]
primitive = "cube"
color = [0.8, 0.3, 0.2, 1.0]
```

```toml
# AFTER — component-driven
[[entity]]
name = "Cube"
[entity.transform]                   # transform stays first-class (it's universal)
rotation_euler = [20, 35, 0]
[entity.components.mesh]             # component name = registered component name
primitive = "cube"
color = [0.8, 0.3, 0.2, 1.0]
# Several [entity.components.X] blocks per entity are allowed.
```

### C# user code (unchanged on the surface)

```csharp
// BEFORE and AFTER — identical
public sealed class Paddle(IInputActionReader<PongAction> actions)
    : KinematicBody2D
{
    public PongAction MoveAction { get; set; }
    protected override void Update(float dt) { … }
}
```

The `Node` base class stays. Inheritance and virtual `Update` stay. What changes
under the hood: `Node`'s constructor no longer registers itself as a "node type" —
it attaches a `ScriptComponent` to its entity that bridges `on_update` →
`Node.Update`. Property setters (`MoveAction`) are still written by the scene
loader, but via component-field metadata instead of reflection lookup.

### Lua user code

```lua
-- BEFORE — 142 lines for 3 node types
local dir_create = cb("ke_node_create_func", function(_ctx, entity, _name) … end)
local dir_set    = cb("ke_node_set_property_func", function(_ctx, entity, key, value)
    local c = ffi.cast("ke_directional_light_component*",
        kernel.ke_ecs_component_get(registry, entity, dir_cid))
    local k = ffi.string(key)
    if     k == "direction" and value.type == V_VEC3 then …
    elseif k == "color"     and value.type == V_VEC3 then …
    elseif k == "intensity"                          then … end
    return 0
end)
…
local types = { make_node_type("DirectionalLight", dir_create, dir_set), … }
```

```lua
-- AFTER — components register their fields once; node-type concept gone.
-- Most components do this from C, not Lua (mesh/camera/lights belong to the
-- framework plugin and ship pre-registered). Lua only writes this when adding
-- a *game-specific* component.
register_component("paddle", ffi.sizeof("paddle_component"), {
    {"move_action", V_INT, offsetof("paddle_component", "move_action_id")},
})
```

Mesh-style logic ("set primitive=cube → bake mesh → attach handle") stops being
a node callback and becomes a system that processes a `mesh_asset_request`
component (or equivalent marker). See §4.5.

---

## 3. Target architecture

### 3.1 Per-component field metadata at registration

```c
// kernel/world/component_field.h (NEW)
typedef struct ke_component_field
{
    const char       *name;     // TOML key inside [entity.components.X]
    ke_variant_type   type;     // expected variant kind
    uint32_t          offset;   // byte offset into the component struct
    uint8_t           count;    // scalar=1, vec3=3, etc. (for arrays)
} ke_component_field;
```

```c
// kernel/world/ecs.h (CHANGED)
KE_API ke_component_id ke_ecs_component_register_v2(
    ke_ecs_registry             *registry,
    const char                  *name,         // matches TOML [entity.components.<name>]
    size_t                       size,
    const ke_component_field    *fields,       // may be NULL for opaque components
    uint32_t                     field_count);
```

Legacy `ke_ecs_component_register(name, size)` stays as a thin wrapper that
calls `_v2` with `fields=NULL, field_count=0`. Components without descriptors
can still exist; they just aren't writable from the scene file.

### 3.2 SceneLoader rewrite

`ke_scene_loader` no longer talks to `ke_node_type_registry`. New contract:

```c
ke_result ke_scene_loader_create(
    ke_allocator    *alloc,
    ke_world        *world,
    ke_scene_tree   *tree,
    const char      *project_root,
    ke_scene_loader **out);
```

Iteration per entity:

1. `tree.create_node(name, parent)` (existing).
2. If `[entity.transform]` is present, apply (existing `apply_transform`).
3. For every `[entity.components.X]` table:
   - `ke_ecs_component_lookup(registry, "X")` → `cid` + field descriptors.
   - `void *comp = ke_ecs_component_add(registry, entity, cid)`.
   - For each key in the TOML table: find matching field, decode variant by
     `field.type`, copy to `comp + field.offset`. Unknown keys are warnings.
4. (Optional, §4.5) If the TOML entry has `[entity.script]`, attach
   `ke_script_component` referencing a registered script type.

`ke_node_type_registry` is **deleted** from the kernel headers. The framework
plugin's `node_type_registry.{h,c}` plus `scene_loader.cpp`'s type-dispatch
path are deleted with it.

### 3.3 C# Node-class layer (sugar over entity + components)

The Pong-flavoured `Node` / `MeshNode` / `KinematicBody2D` / `Paddle` user API
stays. Internally each `Node` constructor:

1. Receives or creates an entity in the world.
2. Attaches a fixed set of components (declared per-subclass — see below).
3. Installs a `ScriptComponent` whose `on_update`/`on_start`/etc. trampoline to
   the virtual `Update`/`Start` methods.

Per-subclass component manifest:

```csharp
public class MeshNode : Node
{
    static MeshNode() => DeclareComponents("mesh", "transform");
    public MeshHandle Mesh
    {
        get => GetComponent<MeshComponent>().mesh;
        set { ref var c = ref GetComponent<MeshComponent>(); c.mesh = value; }
    }
}
```

The scene loader writes the `mesh` component's fields directly — no C# code
runs during loading. The C# `MeshNode` instance is materialised *after* the
load completes by walking entities that should be wrapped (driven by the
`[entity.script]` block or an opt-in flag).

`NodeTypeRegistrar.cs` shrinks from 310 lines to ~80: it now only bridges
script attachment and the property→component-field mapping for the C# wrapper,
not for the scene loader. Reflection use drops sharply.

### 3.4 Asset-loading logic moves to systems

The Mesh node's "set primitive=cube → bake and attach mesh handle" lived in a
node callback. With component-driven loading, the `mesh` component has a
`primitive` *string* field. A new system, `MeshAssetSystem` in the framework
plugin, runs once per frame (or on demand) over entities whose `MeshComponent`
has a `primitive` set but `mesh_handle == KE_HANDLE_NONE`:

```c
// ke_mesh_asset_system_update:
//   query MeshComponent
//   for each entry with primitive[0] && mesh_handle == HANDLE_NONE:
//       bake primitive (cached by name)
//       write mesh_handle
//   leave primitive in place so the system is idempotent
```

Same story for materials: a `color` field → a `MaterialAssetSystem` creates
the material handle on first sight.

This keeps the scene loader pure (data-only) and concentrates engine logic in
the place ECS expects it.

### 3.5 ScriptComponent stays the only "logic" hook

Already exists (`src/c/kernel/include/kernel_engine/kernel/world/components.h`).
The kernel's `ScriptSystem` already dispatches `on_awake`/`on_start`/`on_update`/
`on_late_update`/`on_destroy`/`on_input`. No changes needed beyond making the
C# `Node` constructor install it instead of relying on a node-type callback.

---

## 4. Migration phases

Each phase ends with a green build + Pong (C# *and* Lua) still rendering.

### Phase 1 — Component field metadata (kernel)

- Add `ke_component_field` struct + `ke_ecs_component_register_v2`.
- Add `ke_ecs_component_lookup` (name → cid + descriptors).
- Add `ke_ecs_component_apply_variant` helper (writes one field by name).
- Unit tests in `tests/c/`.
- Old `_register` keeps working unchanged.
- **Acceptance**: kernel tests pass; old API untouched.

### Phase 2 — Component-driven SceneLoader (parallel path)

- New scene-loader code path triggered by file containing `[entity.components.X]`.
- Old `[[node]] type=…` path still works (deprecation warning logged).
- Migrate `examples/csharp/games/pong/scenes/*.scene` to the new format.
- Add a CI test that loads each pong scene and asserts entity/component counts.
- **Acceptance**: every pong scene loads under both paths byte-identically
  (same components, same field values).

### Phase 3 — Asset systems for Mesh/Material

- `MeshAssetSystem`, `MaterialAssetSystem` in framework plugin.
- Add `primitive` (string) and `color` (vec4) fields to MeshComponent /
  MaterialComponent metadata.
- Replace `MeshNode`'s reflection-based property setters with these fields.
- **Acceptance**: a TOML-only `[entity.components.mesh]` produces a rendered
  mesh without any binding code running.

### Phase 4 — C# Node sugar refactor

- `Node` constructor switches from `INodeTypeRegistry.Register` to direct
  entity creation + `ScriptComponent` attachment.
- `NodeTypeRegistrar.cs` slims down (target ~80 lines).
- Pong scripts (`Paddle.cs`, `Ball.cs`, `Scoreboard.cs`) unchanged.
- **Acceptance**: C# pong runs identically to today (visual + audio + scoring).

### Phase 5 — Delete the old path

- Remove `[[node]] type=` support from the scene loader.
- Remove `ke_node_type_registry.{h,c}` and the C# `INodeTypeRegistry` /
  `NodeTypeRegistrar` (replaced by the slim Phase-4 helper).
- Regenerate Lua bindings.
- **Acceptance**: no references to `node_type_registry` in the repo;
  C# pong + Lua pong both run; deleted line count > added line count.

### Phase 6 — Lua pong scene rewrite

- Convert `examples/lua/pong/scenes/Main.scene` to the new format.
- `examples/lua/pong/main.lua` loses all node-type callback blocks
  (~140 lines).
- Add the few game-specific components from Lua (Paddle, Ball state) using
  `register_component`.
- **Acceptance**: Lua pong renders a paddle scene from a TOML file; main.lua
  is under 150 lines.

---

## 5. Open design questions

These should be settled in the first session of implementation, not left to
discover mid-phase:

1. **Wrapper materialisation timing in C#.** Do `Node` C# instances get created
   immediately when the loader sees `[entity.script.cs]`, lazily on first
   accessor call, or via an explicit `tree.WrapEntity<MeshNode>(e)`? Affects
   when constructors run, what GC anchors exist, and what happens if the same
   entity is wrapped twice.

2. **`primitive` field lifetime.** Should the asset system clear the
   `primitive` string after baking (so the field acts like a one-shot request)
   or keep it as the canonical name (so a hot-reload can re-bake)? Hot-reload
   matters more than the few bytes saved.

3. **Hierarchy in the scene file.** Today nested `[[node]] parent="X"` is
   supported. In `[[entity]]` form do we keep `parent = "X"` (sibling-ordered
   resolution) or move to nested tables (clearer but breaks streaming loaders)?

4. **Variant `KE_VARIANT_TABLE`.** Inline TOML tables (used today for
   `properties = { Color = [...], Shape = {...} }`) — do they map cleanly to a
   component field, or do we forbid them in the new format? Forbidding is
   simpler; allowing keeps backward compat for one specific Pong field.

5. **Script attachment syntax.** The TOML way to say "this entity runs the
   Paddle C# class" — `[entity.script.csharp] type = "Pong.Paddle"`, or a
   shorter `script = "csharp:Pong.Paddle"`? Drives how language bindings
   register script factories.

6. **Component naming**. `mesh`, `directional_light`, `camera` — kebab-case,
   snake_case, or PascalCase in TOML? Kernel structs are `ke_X_component`;
   stripping `ke_` and `_component` gives `mesh`. Pick one convention now.

---

## 6. Risk ledger

| Risk | Likelihood | Mitigation |
|---|---|---|
| C# `Node` constructor reorder breaks DI injection ordering in Pong (`IInputActionReader` etc.) | medium | Phase 4 is gated on Pong-running test; revert to old path if injection breaks |
| New scene loader misses an inline-table edge case used in `06_shadow_demo` | medium | Phase 2 keeps both paths in parallel for a milestone |
| `MeshAssetSystem` runs on the wrong thread (sim vs render) — bake calls the renderer | high | Asset system enqueues a request through `ResourceCommandQueue`; bake happens on ke.render exactly like the old NodeTypeRegistrar path |
| Lua bindings regen catches new `_v2` API but breaks the existing `register_type` callers we haven't deleted yet | low | Phase 5 removes both registry types in one commit, regen at the end |
| Deleted `NodeTypeRegistrar` re-enables a known bug from the pre-bbbfd9e era (inline materials) | medium | Phase 4 reuses the existing variant-table code path — only the registration mechanism changes, not variant decoding |

---

## 7. Out of scope (do not creep)

- Threading model changes (`world.update` packet-threading bug #4 stays for a
  separate branch).
- Physics/audio/text plugin FFI exposure to Lua. Pong-in-Lua at the end of
  this branch is **graphical only** — no Box2D, no audio, no Label. Those
  come after, in their own branches.
- Editor / scene-saving direction. The new format is read-only from a tool
  perspective in this branch.
- Removing the C# `Node` base class. We are *preserving* the Node ergonomics;
  any "should Node disappear?" discussion is for after Pong-in-Lua works.

---

## 8. Definition of done

1. C# Pong builds + runs + scores the same way it does today on `main`.
2. Lua Pong runs the same `scenes/*.scene` files as C# Pong (graphically —
   no physics/audio yet).
3. `examples/lua/pong/main.lua` is under 150 lines.
4. Zero references to `ke_node_type_registry` / `NodeTypeRegistrar` outside
   archived/deleted files.
5. `MEMORY.md` updated: deprecated entries removed, new ECS-pure component
   model documented as the canonical scene-loading path.
