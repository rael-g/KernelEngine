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

### Phase 4 — C# Tree.WrapEntity hook (scope revised)

The original plan called for slimming `NodeTypeRegistrar.cs` from 310 → ~80
lines by switching `Node` to use `ScriptComponent`. Two discoveries during
implementation forced a narrower scope:

1. C# moved AWAY from `ScriptSystem` deliberately in commit `ca382e4` (May
   2026) because the kernel iterates entities in ECS storage order while
   `Tree.TickUpdate` walks pre-order — children-after-parents matters for
   Pong's Scoreboard / Label hierarchy.
2. `NodeTypeRegistrar` does much more than property dispatch (inline
   Material, Shape2D, `res://` resolution). Most of that should be native
   (see §7a) but migrating it would break C# Pong without the equivalent
   native paths existing first.

So Phase 4 lands the minimum that unblocks Phase 5/6 without breaking C# Pong:

- `Tree.WrapEntity<T>(ulong entity)` materialises a typed C# wrapper on
  demand for entities the SceneLoader created from the new component format
  (decision #1 of §5).
- Legacy `[[node]]` path and `NodeTypeRegistrar` stay untouched.
- C# Pong runs unchanged.
- **Acceptance**: `Tree.WrapEntity` tested; all 171 framework tests + 188
  kernel tests + 20 config tests green.

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

## 5. Design decisions (locked at session start)

1. **Wrapper materialisation timing in C#**: **explicit** via
   `tree.WrapEntity<Paddle>(entity)`. The loader only fills components;
   wrappers materialise when C# game code asks for one. Avoids creating GC
   roots for entities that stay pure data (lights, camera, decorative meshes).

2. **`primitive` field lifetime**: **canonical** — asset system reads it and
   leaves it in place. Costs ~32 bytes per mesh node; enables hot-reload and
   keeps the field a self-describing source of truth.

3. **Hierarchy in the scene file**: **flat `parent = "X"` reference**.
   Identical to today. Nested tables would break streaming loaders and add no
   ergonomic win.

4. **`KE_VARIANT_TABLE` (inline TOML tables)**: **forbidden** in the new
   format. Inline `Material { color=[...] }` was the root cause of bug 3c3bd92
   (silent null materials). Each previously-inline payload becomes its own
   component instead.

5. **Script attachment syntax**: **explicit `[entity.script]` block**:
   ```toml
   [entity.script]
   language = "csharp"
   type     = "Pong.Paddle"
   ```
   More verbose than `script = "csharp:Pong.Paddle"` but leaves room for
   future per-script properties (`auto_start = false`, etc.).

6. **Component naming in TOML**: **snake_case**, derived from the C struct by
   stripping the `ke_` prefix and `_component` suffix. `ke_mesh_component` →
   `mesh`; `ke_directional_light_component` → `directional_light`. Matches the
   kernel naming convention.

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

## 5b. Scene-property authoring decision (Phase 5)

User-defined `Node` subclasses (e.g. `Pong.Paddle`) carry scene-authored
properties like `MoveAction = "PaddleLeftMove"`. The legacy path used
reflection in `NodeTypeRegistrar.cs`. Deleting reflection without a
replacement breaks scene authoring of arbitrary node classes. Considered three
replacements (mirrors of Unity `[SerializeField]` / Godot `[Export]`):

| Option | Per-class user burden | Compile-time safety | Runtime reflection | Engine cost |
|---|---|---|---|---|
| **A** — `[SceneProperty]` + source generator | annotation only | ✅ | none | high (separate .csproj) |
| **B** — manual `SceneProperties.Register<T>(…)` | 1 line per property | ✅ | none | low |
| **C** — generic `[entity.properties]` bag, `Properties.Get<T>("key")` in `Start()` | 1 line per property in `Start()` | ❌ (string keys) | none | low |

**Decision (locked at session start of Phase 5)**: **C now, A later.**

Reasoning: C closes this branch quickly without changing the public API surface
that the future GUI/CLI editor will own. When the editor lands, source
generators slot in on top of C without breaking the bag — `[SceneProperty]`
properties auto-populate the same dictionary the bag exposes today. C is the
short path; A is the long-term ergonomic target.

The bag implementation:
* `ke_scene_loader.register_properties_callback(callback, ctx)` — analogous
  to `register_script_language`, called once per `(entity, key, value)`
  parsed from `[entity.properties]`.
* C# binding stashes everything into `Dictionary<entity, Dictionary<string,object>>`.
* `Node.Properties` accessor on the C# side reads from that dictionary.
* The 4 built-in `Node` types (`AudioPlayer`, `CollisionBody2D`,
  `CollisionShape2D`, `Label`) refactor their `Start()` to pull from
  `Properties.Get<T>(…)` instead of reflection-set fields.
* After the load finishes the dictionary stays alive — the loader does not
  forget — so dynamic property reads (game code that asks "what is my
  Path?") work after Start too.

Deferred to S8 (or whenever the GUI/CLI editor lands):

* **Option A — `[SceneProperty]` + source generator.** Gives compile-time
  safety, IDE autocomplete in property lookups, and removes the stringly-
  typed `Properties.Get<T>("name")` call. Source generator (
  `Microsoft.CodeAnalysis`) walks `[SceneProperty]`-annotated members on
  every partial class derived from `Node`, generates a typed
  `ApplyProperty(node, key, variant)` method, and registers it with the
  engine at module init. The bag mechanism stays as the fallback for
  late-bound properties (TOML keys the source generator didn't see).

## 7a. Native-opportunity backlog (discovered during Phase 4)

Work this refactor flagged as belonging on the native side but did NOT execute
(out of scope for this branch — added here so we don't lose them):

1. **Inline `Material` resolution** — `NodeTypeRegistrar.BuildInlineMaterial{,FromDict}`
   converts a TOML table `{ base_color = [...], metallic = 0.0, roughness = 0.5 }`
   into a GPU material via `ResourceManager.CreateMaterialAsync`. The same
   shape exists in C# Pong scenes (Paddle, Ball, Wall). Should become a native
   asset system that observes a `material` component with `base_color` /
   `metallic` / `roughness` fields and writes the resolved handle, mirroring
   Phase 3's `ke_mesh_asset_system`.

2. **Inline `Shape2D` resolution** — `NodeTypeRegistrar.BuildShape{,FromDict}`
   produces `RectangleShape2D` / `CircleShape2D` from
   `{ kind = "rectangle", half_extents = [...] }` and friends. Belongs as a
   component variant (or two components: `shape_rectangle`, `shape_circle`)
   that physics systems consume directly. Removes a C#-only TOML interpreter
   from the data path.

3. **`res://primitives/<name>` mesh resolution** — currently routed through
   `IAssetResolverBackend.ResolveMesh` → C# `ResourceManager.CreateMeshAsync`.
   Overlaps with Phase 3's primitive-name field. Picking one canonical path
   (string field on `mesh` component, processed by `ke_mesh_asset_system`)
   drops the resolver hop and the C#-side reflection that maps the property.

4. **`res://*.material` file resolution** — `IAssetResolverBackend.ResolveMaterial`
   reads a `[material]` TOML section into a `MaterialSpec` C# struct. The
   parsing is already C++ (in `material_file.cpp`), but the spec returns to
   C# only to be re-fed to `CreateMaterialAsync`. The whole loop should run
   native: SceneLoader observes `material_path` string field → asset loader
   parses → asset system creates handle.

5. **`Tomlyn.Model.TomlArray → Vector2/3/4/Quaternion` conversion** —
   `AsVector2/3/4/AsQuaternion`. The new scene loader already produces
   `ke_vec*` variants directly; this fallback path exists for the legacy
   C# scene loader and is dead code once Phase 5 lands.

6. **Reflection-based property setting** — the whole `prop.SetValue(node, …)`
   path in `ApplyProperty`. Replaced by `ke_ecs_component_apply_variant` for
   plain types in Phase 1; remains live for advanced types listed above. Once
   each advanced type has a native component representation, the reflection
   path can be deleted along with `NodeTypeRegistrar`.

7. **Pre-order tree-walk tick order** — `Tree.TickAwakeAndStart/Update/LateUpdate`
   exists because the kernel `ScriptSystem` iterates entities in ECS storage
   order, not parent-first tree order (commit `ca382e4`, May 2026). A future
   `ke_script_system_v2` that walks the hierarchy in pre-order would let the
   C# tree-walk dispatcher go away and the kernel become the single script
   driver again — relevant if we want Lua scripts to participate in the same
   ordering guarantees.

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

## 7c. Remaining cleanup at branch close (Phase 5.6 partial)

The big-ticket goal of the refactor — **delete the 310-line reflection-based
`NodeTypeRegistrar`** — is done. C# Pong and Lua Pong both load through
`[entity.script]` + `[entity.properties]`; the SceneLoader's dispatch goes
through the script factory + scene_properties component path; the legacy
`NodeTypeRegistrar.ResolveNodeType` reflection beast is replaced by a 30-line
`NodeTypeResolver` (type-name lookup only). 514 tests green (255 kernel + 359
C#) end-to-end, both pongs run.

What still lives in the tree at branch close, deferred to a follow-up:

1. **`INodeTypeRegistry` C# interface** + `NodeTypeRegistry.cs` native wrapper
   stay referenced (Tree constructors, Application, IFrameworkBackendFactory)
   even though no code path actually uses them anymore. Deleting them is a
   pure cascade of signature changes — defer with the rest below.
2. **Legacy `[[node]] type=…` path in `scene_loader.cpp`** still compiles and
   runs (the C ABI `ke_node_type_registry` underneath it survives). The C++
   `test_scene_loader` suite still has 15 `[[node]]` cases on it, so removing
   the legacy path means migrating those tests too.
3. **`ke_node_type_registry` / `ke_node_type` C ABI** stays in the kernel
   framework headers, used only by the legacy [[node]] path above.
4. **Lua bindings** still expose `ke_node_type_registry_*`; the Lua pong
   doesn't touch them anymore (Phase 6-early already migrated), but the
   regenerated bindings carry them.

These four cleanup tasks are 100% mechanical and have no design risk — they
just touch a lot of files. Picking them up in a focused follow-up branch keeps
the diff reviewable and lets us re-merge `main` first.

## 8. Definition of done

1. C# Pong builds + runs + scores the same way it does today on `main`.
2. Lua Pong runs the same `scenes/*.scene` files as C# Pong (graphically —
   no physics/audio yet).
3. `examples/lua/pong/main.lua` is under 150 lines.
4. Zero references to `ke_node_type_registry` / `NodeTypeRegistrar` outside
   archived/deleted files.
5. `MEMORY.md` updated: deprecated entries removed, new ECS-pure component
   model documented as the canonical scene-loading path.
