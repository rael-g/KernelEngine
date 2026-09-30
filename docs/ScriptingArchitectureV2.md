# Scripting Architecture V2 — the language-agnostic node host

> **Superseded in scope by [`ScriptingArchitectureV3.md`](ScriptingArchitectureV3.md)**, which owns the end-to-end multi-language strategy. This document is now historical record only — **`ke_node_host` itself was rejected** (built and reverted 2026-08-05; see V3 §7.14.4 for the audit and its replacement, `node.h`/`node3d.h`/`node2d.h` as generated node base types). Kept alongside the two rejected designs it already documents (§9.1, §9.2) for the same reason: the *why-not* is worth keeping even after the *what* is gone. Read V3 §7.14 for the current design.

**Status**: **Rejected 2026-08-05, after a full implementation.** Two spikes (branch `spike/zig-pong`) had already proved the *thesis* — one native middle-end can own node-registration mechanics for every language — but the mechanism they used (a serialized TOML IR, "INR") was discarded first (§9.2). The revised mechanism here, a **transactional builder API** on a `ke_node_host` contract, was then built in full — native Zig, a `kabic`-generated C# wrapper, a hand-written `[UnmanagedCallersOnly]` dispatch trampoline, verified end-to-end against a real flecs `ke_ecs` + enkiTS `ke_runtime` — and reverted the same day. Cause: this document predates `kabic` and the Roslyn `NodePropertyGenerator`, and assumed an SDK model where one native service owns field declaration, component layout, and registration. Under V3, all three are already owned elsewhere (`components.h`+`kabic` for engine types, `NodePropertyGenerator` for game-authored ones, `ke_scene_tree` for entity creation) — so `ke_node_host`'s type-builder half was a second, disconnected source of truth for facts the architecture had already settled, not a missing piece. Only the dispatch trampoline (segment-granularity native→managed callback) survived; it lives inside `node.h`'s lifecycle surface now. The spike code on `spike/zig-pong` remains reference material only, never a base to merge (it predates the CMake→`build.zig` migration and the framework's C→Zig port by ~180 commits).

**Supersedes**: [`FrameworkArchitectureV2.md`](FrameworkArchitectureV2.md) §5 ("C# ergonomics layer — source generator + script safety model") as the mechanism for node-registration ergonomics. §5's `NodeBehavior`/`ref struct View`/fields-as-components **UX goals are not superseded** — they are still what a C# author should feel — but the mechanism realizing them changes: no per-language reimplementation of "fields → component, hooks → system", one native middle-end owns it. See §9 for the precise reconciliation.

**Audience**: Engine maintainer + future language-binding authors (C#, Python, Lua, …).

**Companion docs**: [`RuntimeArchitectureV2.md`](RuntimeArchitectureV2.md) §15 (script safety model — this design is a concrete implementation of its "single doorway" doctrine for the node-registration problem specifically). [`KernelArchitectureV2.md`](KernelArchitectureV2.md) §2 (tier criterion — placement rationale, §3 below). [`Kanban.md`](Kanban.md) Tier S (tracking; this doc is the authoritative design, Tier S is authoritative for scheduling/status).

---

## 1. The problem

Supporting a new scripting language costs four things:

1. **Low-level FFI bindings** — mechanical, irreducible, already solved by ClangSharp for C# (`KernelEngine.*.Native`).
2. **Hand-written wrapper ergonomics** — the typed surface a script *calls out to*: scene-graph ops, input maps, audio players, camera/light/mesh node types. Today that's `src/csharp/toolkit` (~1585 hand-written LoC).
3. **The registration mechanics** — "a struct's fields become an ECS component, a lifecycle method becomes a system with an access-list". Hand-written today for the one language we have; `FrameworkArchitectureV2.md` §5 planned to reimplement it a second time as a C# Roslyn source generator.
4. **The semantics themselves**, duplicated inside (2) and (3).

Item 3 is what this document solves. It is small in absolute size (~150 lines of layout math and vtable calls) but it is **semantically load-bearing**: every reimplementation is a place where languages can drift from each other on what a valid field type is, what an access string means, how a hook maps to a phase. Drift between language bindings is the failure mode the project must avoid *before* committing to multi-language scripting.

**Item 2 is the larger `O(N)` and this design does not address it** — see §12.1. Naming that honestly matters more than solving item 3 elegantly.

---

## 2. The architecture — front-end / middle-end / back-end

```
Player.cs (game code)  ──frontend──►  Player.g.cs  ──┐
                                      (builder calls  │
                                       + dispatch glue,│
                                       one pass, one   │
                                       source of truth)│
                                                       │
                                          ke_node_host │ (middle-end, Zig, native)
                                          verifies field types, resolves
                                          component references, maps hooks
                                          to phases, registers the node's
                                          own component + the backing
                                          runtime system, owns spawn()
                                                       │
                                          per-segment dispatch
                                                       │
                                          Player.OnUpdate(...) ◄── user code, zero interop
```

Three roles:

- **Frontend** (per language — **not built by either spike**, mandatory long-term): translates native syntax (`class Player : Node { float speed; void OnUpdate(...) }`) into builder calls plus the matching dispatch glue. Owns *no* semantics. It is inadmissible for an author in any supported language to hand-write a line of Zig or a registration call by hand in the shipped product; the frontend runs automatically as a build step (a Roslyn incremental generator for C#) or, for a dynamic language, is replaced entirely by runtime introspection calling the builder directly.
- **Middle-end** (`ke_node_host`, Zig, this design's deliverable): consumes builder calls, verifies them, does every mechanical registration step once. This is the reusable part.
- **Back-end / SDK** (per language, thin): a small hand-written library (`KernelEngine.Scripting`, ~150 LoC for C#) giving the language a `Node` base class to compile against, plus the runtime glue (the `NodeHost` wrapper and the native↔managed trampoline). Distinct from the frontend: the SDK ships once; the frontend runs per-project at build time.

**Design principles this encodes** (and §9.2 explains why the LLVM-style *serialized* IR is not among them):

1. **The narrow waist already exists — it is the C ABI.** `ke_ecs` + `ke_runtime` are already a language-agnostic, verified contract every language must speak. `ke_node_host` sits on that waist; it does not introduce a second one.
2. **Frontends lower, they never own semantics.** All meaning (valid field types, access strings, hook→phase mapping) lives in the middle-end's verifier, so languages structurally cannot drift.
3. **Registration is transactional.** Verification runs before any `component_register`/`register_system` call; a bad declaration fails `commit()` with a descriptive `ke_error` and registers nothing. Half-registered node types are not a representable failure mode. This is a property of the *API's* transactionality, not of having an IR.
4. **The same path serves AOT and dynamic languages.** A static language's frontend emits builder calls at build time; a dynamic language's binding makes the same calls at import time. No codegen step and no serialization round-trip for the dynamic case.

---

## 3. Where this lives — kernel-doctrine placement

Per `KernelArchitectureV2.md` §2's tier criterion (*"does the scheduler or the ECS need this to run a system?"*), `ke_node_host` is **not** kernel substrate — the scheduler and ECS run perfectly well without it. It is a **Tier 3 domain / framework concept**, the same tier as `ke_scene_tree` and `ke_scene_loader`: a policy layer built *on top of* `ke_ecs`+`ke_runtime`.

Mirroring the existing framework-domain shape:

- **Contract** (vtable only, no policy): `src/zig/framework/include/kernel_engine/framework/node_host.h`, alongside the existing `scene_tree.h` / `scene_loader.h` / `world.h`.
- **Factory**: `node_host_create.h` — `ke_node_host_create(ke_ecs*, ke_runtime*, ke_error**)`, both borrowed, returning a `ke_node_host_handle{ref, destroy}` owner-wrapper per the handle-ownership convention.
- **Impl**: inside the existing `src/zig/framework/` plugin (`src/node_host.zig`), which is one Zig plugin with one `build.zig` — **not** a nested sub-plugin with its own build. No TOML parsing means no third vendored `tomlc99` copy.
- **Bindings**: regenerated via `dotnet run scripts/generate_bindings.cs` from a `.rsp` (pinned rule: never hand-write bindings), following the `--remap`/`--exclude`/`--with-using` conventions every other `.rsp` uses.

This placement means a hypothetical second ECS/runtime implementation does not need its own node-host reimplementation — `ke_node_host` depends only on the `ke_ecs`/`ke_runtime` contracts, not on flecs or the enkiTS-backed scheduler specifically.

---

## 4. The type-builder — declaring a node type

The builder is the middle-end's input. It replaces INR (§9.2) and carries the identical verification guarantees.

```c
// Field types reuse ke_variant_type — the engine's existing type table
// (BOOL/INT/FLOAT/STRING/VEC2/VEC3/VEC4/QUAT/TABLE). No second type system.
ke_node_type_builder *b = host->begin_type(host, "Player", &err);

b->field(b, "speed",  KE_VARIANT_FLOAT);   // → the node's own component; layout is
b->field(b, "health", KE_VARIANT_INT);     //   declaration order, C alignment rules.

ke_node_hook_id h = b->hook(b, KE_HOOK_UPDATE, on_update_fn, ctx);
b->access(b, h, "position", KE_ACCESS_RW); // external component, resolved at commit
b->access(b, h, "Player",   KE_ACCESS_RW); // self-reference to the node's own component

host->commit(host, b, &err);               // verify all → register atomically, or nothing
```

**Verifier rules (all enforced inside `commit`, before any `component_register`/`register_system` call)**:

- Type name required, must not already be loaded on this host.
- At least one `field`; every field's type must be in the `ke_variant_type` table. Unsupported-in-a-component types (e.g. `STRING`, `TABLE` — not blittable into raw component memory) are rejected by name.
- Every hook id must be in the host's hook table (§7) and maps to a fixed runtime phase.
- Every `access` component name either equals the type name (self-reference, resolved to the just-registered own component) or must already exist on the `ke_ecs` (`component_lookup` failure → `KE_ERROR_NOT_FOUND` naming the missing component).
- Access count per hook is capped at `KE_QUERY_MAX_TERMS` (the existing engine-wide query-term limit) — exceeding it is a `commit()` error, not silent truncation.

On any failure `commit` returns `false` with a populated `ke_error`, registers nothing, and the builder is destroyed. Per project doctrine there is no `assert`/`abort` on any path.

**Why the builder beats a serialized document, in one line**: the registration call and the dispatch-time column cast are emitted by the *same* frontend pass from the *same* source, so they cannot disagree. With two generated artifacts (a `.toml` and a glue file) that must independently agree on column ordering, disagreement is silent memory corruption. See §9.2.

---

## 5. `ke_node_host` contract

```c
typedef void (*ke_node_hook_fn)(void *ctx, const ke_entity *entities,
                                void *const *columns, size_t count, float dt);

typedef struct ke_node_host {
    void *handle;
    ke_node_type_builder *(*begin_type)(self, const char *type_name, ke_error **);
    bool       (*commit)(self, ke_node_type_builder *, ke_error **);
    ke_entity  (*spawn)(self, const char *type_name, ke_error **);
    bool       (*attach)(self, ke_entity, const char *type_name, ke_error **);
    bool       (*describe)(self, const char *type_name, ke_variant_table **out, ke_error **);
} ke_node_host;  // + ke_node_host_handle{ref, destroy}
```

- **`begin_type` / `commit`**: §4. A second `commit` of an already-registered type name is a hard error, not a silent replace — hot-reload semantics are an explicit open question (§11).
- **Dispatch**: `columns[i]` order at dispatch time = `access()` declaration order for that hook. **Granularity is one call per archetype segment, not per entity** — this is the load-bearing performance decision: a managed language pays one native→managed transition per segment (potentially hundreds of entities), not per entity. Internally each hook becomes one `ke_runtime` system whose native `execute` callback walks `ke_system_ctx_view` per `RuntimeArchitectureV2.md` §15's "single doorway" doctrine and calls the bound `ke_node_hook_fn` once per resolved segment.
- **`spawn`**: creates an entity carrying every component the type declares (zero-initialized). Deliberately dumb — the caller sets initial field values after spawn (no field defaults in v0, §11).
- **`attach`**: the same, onto an entity that already exists. This is what lets `ke_node_host` serve as a `ke_scene_loader` script factory (§8).
- **`describe`**: introspection as an *output* — dumps a registered type's fields/hooks/accesses as a variant table for tooling and diagnostics. This is deliberately the inverse direction from the discarded INR: a serialized description is something the host *produces* for inspection, never something it *consumes* to decide semantics.

---

## 6. The C# SDK/frontend split

**SDK** (`src/csharp/scripting/KernelEngine.Scripting/`, ships once, hand-written, ~150 LoC):

- `Node` — abstract base holding `Entity` identity. Exists so `class Player : Node` is a valid, recognizable declaration for the frontend to find.
- `NodeHost` — managed wrapper over `ke_node_host`: `BeginType`/`Commit`/`Spawn`/`Attach`, plus the `[UnmanagedCallersOnly]` trampoline and `GCHandle`-pinned dispatcher lifetime management.

**Frontend output** (`Player.g.cs`, one file per node type, emitted by the Roslyn generator): a blittable mirror struct per external component referenced, a mirror of the node's own fields, and a `Register(NodeHost)` static method that makes the builder calls **and** installs the dispatcher that walks the segment and casts each column — both emitted together, from one analysis of `Player.cs`.

**User code** (`Player.cs`): plain C# fields + hook bodies. Zero `unsafe`, zero interop attributes, zero ECS API calls — the exact ergonomics bar `FrameworkArchitectureV2.md` §5 aimed for, reached by a different mechanism.

```csharp
public partial class Player : Node
{
    public float speed;
    public int health;

    public void OnUpdate(ref Position position, float dt)
    {
        position.X += speed * dt;
    }
}
```

**Compile-time diagnostics belong to the frontend.** The Roslyn generator mirrors the field-type table so an unsupported field type is a squiggle on the field, not a runtime string. It does not *own* that table — `commit()` remains the single source of truth and catches a stale mirror at runtime. This mirrors how clang reports type errors itself rather than deferring to LLVM's verifier.

---

## 7. Known gaps and honest limitations

- **Hook table is minimal.** `OnUpdate → KE_PHASE_UPDATE` is the proven case. `OnBind`/`OnReady`/`OnUnbind` (the C# `Node` lifecycle today) need their phase mapping decided — `OnReady → KE_PHASE_STARTUP`, `OnBind` running at spawn rather than in a phase at all. Additive, not a redesign.
- **No hot-reload semantics.** A second `commit()` of an already-registered type name is a hard error (§11).
- **Per-instance managed overhead.** Materializing a managed `Player` per segment row must index by dense row position (matching how `ke_ecs_segment` hands back contiguous columns), not by hashing entity IDs — the spike's `Dictionary<ulong, Player>` is adequate for a spike and wrong for production.
- **Field reflection is currently dead in the ECS.** `ke_component_field` exists as a struct, but `ke_ecs.component_register` takes only `(name, size)` and the flecs impl returns `fields = null` from `component_lookup`. Scene-authored property application does *not* go through field reflection today — it goes through per-component apply callbacks registered via `ke_world.register_component_apply`. This is good news for §8: `ke_node_host` can synthesize a generic apply callback from its own declared field list (name + variant type + offset) and register it on that existing seam. No new ECS vtable slot, no `component_register_v3`.
- **No array/nested-struct field types.** `ke_variant_type` covers scalars plus VEC2/3/4 and QUAT, which is more than the spike's INR had; arrays and nested structs are still open.

---

## 8. Relationship to scenes — types vs. instances

`examples/csharp/games/pong/scenes/*.scene` are **instance data** (which entities exist, at what transform, with what property overrides), parsed by `src/zig/framework/src/scene_loader.zig`. A node type declaration is **type data** (what fields/hooks/access a type has). They are different concerns and must never be conflated.

The convergence point: `scene_loader.zig`'s script dispatch calls one globally-registered `ke_script_factory_func(ctx, entity, type_name, out_error)` whenever a scene entity carries `type = "Pong.Ball"`. **`ke_node_host` is a natural implementation of that factory** — on seeing `type_name`, look it up among registered types and `attach()` the declared components onto the entity the scene loader already created. That is exactly why `attach` exists as a first-class contract slot (§5) rather than being bolted on later.

Combined with the apply-callback synthesis noted in §7, this closes the loop: a scene file can both *instantiate* a node-host type and *override its properties*, with no new ECS surface.

---

## 9. Reconciliation with prior designs

`FrameworkArchitectureV2.md` §5 planned a five-phase Roslyn source generator (`[SceneNode]` discovery → `ref struct View` → `NodeBehavior` → fields-as-components → AOT analyzer) that would **own** the fields→component/hook→system mechanism, emitting C#-specific registration logic with no native counterpart. That is superseded as the *mechanism* — building it would mean C# owns its own copy of exactly the logic `ke_node_host` centralizes, reintroducing the duplication problem for the very first language.

**What carries forward unchanged**: the UX bar. `NodeBehavior`, fields-that-feel-like-fields, and the `ref struct View` funnel's compile-time guarantee that component access cannot escape the stack all still describe what a C# author should experience. The reconciled shape: the Roslyn `IIncrementalGenerator` becomes the **frontend** (§2), emitting `Player.g.cs` using the incremental-generator infrastructure §5.2 already scoped. It does not independently decide what a valid field type is — `commit()`'s verifier is the shared source of truth.

### 9.1 — Abandoned design A: Zig comptime emitting C# directly

An early version of the spike had Zig comptime *generate* C# (`nodegen --backend csharp`, schema authored as a Zig struct compiled into the generator). Abandoned mid-session: Zig comptime reflection resolves at the *reflecting program's own* compile time, so "schema in Zig" would have required rebuilding the generator per schema and could never accept a schema produced by a non-Zig frontend.

### 9.2 — Abandoned design B: INR, the serialized TOML IR

The second spike shipped **INR** — a TOML document per node type (`[node]`/`[[field]]`/`[[hook]]`/`[[component]]`) parsed and verified by a native middle-end, explicitly modelled on LLVM IR. It worked end-to-end. It is discarded anyway, for reasons that only became visible once the LLVM analogy was examined instead of assumed:

**The LLVM analogy does not hold on any of the three axes that make LLVM IR pay for itself.**

| LLVM | Here |
|---|---|
| Middle-end is enormous (100+ passes). The ratio of shared work to per-frontend work is huge. | Middle-end is ~150 lines of layout math and vtable calls. The INR parser + verifier + a vendored `tomlc99` (2392 lines) is **larger than what it centralizes**. |
| The problem is **M×N** — M languages × N targets. IR collapses M×N to M+N. | The problem is **M×1**. There is exactly one target: the `ke_ecs`/`ke_runtime` C ABI. A second ECS implementation is another *provider of the same contract*, not a second target. |
| The IR is a lossy lowering — source semantics genuinely disappear, which is what makes it reusable. | INR loses nothing; it is a 1:1 re-serialization of what the C call already expresses. |

The middle row is decisive: **IR collapses M×N to M+N; with N=1 it collapses M to M+1.** INR added a layer rather than removing one. The C ABI was already the narrow waist.

**Concrete harm, beyond inelegance:**

- **Two generated artifacts that must agree, with nothing checking them.** INR's contract was that `columns[i]` order equals `[[component]]` declaration order, "which the SDK knows because it emitted the same INR". If `Player.toml` and `Player.g.cs` ever drift, a column gets cast to the wrong mirror struct — silent memory corruption. The builder makes both come from one pass, so the failure mode ceases to exist.
- **Diagnostics move to runtime.** An unknown field type surfaces as a `ke_error` string at load time instead of a squiggle on the field. LLVM does not suffer this because clang has its own diagnostics and does not lean on the verifier; INR's design explicitly made the native verifier the sole authority, which forces the frontend to either duplicate the table (defeating the point) or report poorly.
- **A second type system.** INR invented its own scalar-only field table, generating a backlog of questions — no vec3, no arrays, no strings, field defaults, INR versioning — none of which exist if field types are `ke_variant_type`, which the engine already defines and already uses for scene properties.
- **A third vendored copy of `tomlc99`** to solve a problem that needs no parser.

**Prior art points the same way.** Godot is the closest thing to an engine usable from any language (GDScript, C#, Rust, Swift, Nim, D on one C ABI): user types register through **direct C ABI calls** (`classdb_register_extension_class` and friends); its serialized `extension_api.json` describes *the engine's own API to binding generators*, not user types. Unreal's UHT is precisely the "frontend scraper" pattern, but what it emits populates a **runtime reflection registry** (`UClass`/`UProperty`) that Blueprint and Python then bind against. flecs — already in this engine — registers reflection by direct calls with JSON as an optional output. The consistent industry answer is *registry populated by ABI calls, with serialization reserved for describing the engine to binding generators*.

Schema-first codegen (Protobuf, FlatBuffers, WinRT `.winmd`) is a successful pattern, but it earns its cost by crossing a process, machine, or independent-versioning boundary between parties that never see each other's source. A frontend and a middle-end in the same build, same process, same version have no such boundary to pay for.

**What survives from INR**: the transactional-registration guarantee, the single-native-verifier property, and the AOT/dynamic duality — all three are properties of the middle-end being one native implementation, and none of them required serialization. **Reversibility note**: if an offline artifact is ever genuinely needed (cooking node types into an asset package), serializing a sequence of builder calls is trivial, and `describe` (§5) already emits the same information. The reverse — starting from text and later wanting a live API — is where the spike was stuck.

---

## 10. Implementation plan

1. **`ke_node_host` builder core** (native): `begin_type`/`field`/`hook`/`access`/`commit`/`spawn`/`describe`, in `src/zig/framework/`, with the full verifier and a negative-test corpus as a `zig build test` target in that plugin. The spike's `node_host.zig` registration path, `hookTrampoline`, and segment walk port over nearly intact; the TOML layer is dropped.
2. **Full hook table + phase mapping** (`OnBind`/`OnReady`/`OnUnbind`, §7) and the synthesized apply callback so scene-authored properties can target node-host-declared components (§7/§8).
3. **`attach` + `ke_scene_loader` script factory wiring** (§8), so `.scene` files reference node-host types by name exactly like they reference hand-registered C# node types today. Validates the types-vs-instances seam for real.
4. **C# frontend** (Roslyn `IIncrementalGenerator`, §9): emits `Player.g.cs` from `class Player : Node` declarations, with compile-time diagnostics for unsupported field types.
5. **Pong (or a comparable real game) fully on this pipeline in C#** — not a big-bang rewrite of `Toolkit`; `Toolkit` content migrates opportunistically.
6. **A second language** (Python or Lua) gets a frontend + SDK. **This is the actual test of the thesis**: if it costs one frontend plus a ~150-LoC SDK and zero native changes, `O(1)` is proven in production rather than by construction. Note that a dynamic language should skip codegen entirely and call the builder from runtime introspection — a capability INR would have made strictly worse (generate TOML, then parse it back, at process start).

---

## 11. Open questions

- **Hot reload**: does re-registering a changed type replace the definition and migrate already-spawned entities, or is it rejected? Deferred until a workflow forces the decision.
- **Field defaults**: should `field()` take an optional default `ke_variant` so `spawn` can zero-init to something else? Not needed yet; likely needed once a real game ships.
- **Non-blittable field types**: `ke_variant_type` includes `STRING` and `TABLE`, which cannot live in raw component memory as-is. Reject them outright (current plan) or define an indirection (interned handle)?
- **Arrays and nested structs**: still unaddressed, and now clearly an *ECS type-table* question rather than a scripting one — which is the right place for it.
- **Does a dynamic language want a build-time frontend at all?** Almost certainly not — it should call the builder from runtime introspection. Confirm when a binding is actually built.

---

## 12. Non-goals and what this does *not* solve

Python/Lua SDKs until a language is actually prioritized. Replacing the ClangSharp-generated low-level P/Invoke bindings (`KernelEngine.*.Native`) — those remain the substrate `ke_node_host`'s own bindings and every composition root sit on. Multi-threaded hook dispatch beyond what `ke_runtime`'s wave scheduler already provides. A GUI/editor authoring surface for node types.

### 12.1 — What this design does *not* solve: the consumed API surface

`ke_node_host` solves **registration**. It does not solve **the API surface a script consumes**. A node body that only reads and writes its own components is fully served. The moment it wants to play a sound, query an input action, spawn a child, raycast, or set a camera's FOV, it needs some typed access — and today that is `src/csharp/toolkit`, hand-written.

Breaking down the Toolkit's ~1585 LoC:

- **Replaced by `ke_node_host`** (~600 LoC): `Scene/Node.cs` (base class + hook plumbing), `Scene/View.cs` (the ref-struct funnel — the host's `columns[]` handoff subsumes it), `Scene/NodeTypeRegistry.cs`, `Modules/SceneNodesModule.cs`, and the component-access half of `Scene/NodeWorld.cs`.
- **Survives** (~900 LoC): the scene-graph half of `NodeWorld` (`AddNode`/`Find`/`DestroyNode`), `Input/InputActionMap`, `Text/Font` + `Label` + `LabelUiSystem`, `Scene/AudioPlayer`, `Assets/ModelExtensions`, `SceneRouter` + `SceneRouterModule`, `CollisionShape2D`/`IPhysicsBody2D`, and the typed node family (`Camera`, `MeshRenderer`, lights, `Skybox`, `Sprite2D`).

**But this residual cost does not scale with N languages.** The Zig spike is direct evidence (§13): it consumed `ke_physics_2d`, `ke_input_actions`, `ke_render_service`, `ke_window`, and `ke_ecs` with **zero** binding or wrapper layer, calling vtable slots inline (`api.engine.physics.*.create_body.?(...)`), because `@cImport` ingests the C headers natively.

The governing variable is **the distance between the target language and C**, not the number of targets:

| Language class | Binding cost (item 1) | Wrapper cost (item 2) | Why |
|---|---|---|---|
| Zig / C / C++ | ~0 | ~0 | Ingests C headers; a struct is a struct; raw pointers are idiomatic |
| Rust | small (bindgen) | small | `unsafe` blocks are acceptable at the boundary |
| Python / Lua | ~0 (cffi / LuaJIT FFI) | small | Dynamic — no static mirror types to author |
| **C#** | **~3800 generated LoC** | **~5000 hand-written LoC** | Static, managed, GC'd; cannot ingest C headers; `unsafe` is banned in script code by `RuntimeArchitectureV2.md` §15's safety model |

**C# is the outlier, not the template.** The correct strategic conclusion is therefore *not* to build machinery that generalizes the C# apparatus across N languages — it is to **shrink the C# apparatus**, which is exactly what `ke_node_host` does for the registration third of it. A future Python or Lua binding should be expected to cost far less than C# did, and any design that assumes otherwise is over-fitting to C#'s constraints.

**Two things remain genuinely irreducible**, and the Zig spike confirms both rather than refuting them:

1. **An access funnel is inherent, not a C# artifact.** The Zig spike grew `NodeApi` (transform access + `spawnChild`) for the same reason C# has `View` — a hook body needs a scoped handle to the world, in any language.
2. **A composition root must exist somewhere.** The spike's `main.zig` is 233 lines of raw C ABI doing by hand what C#'s `ServiceCollection` + module registration does: device/window/ecs/scheduler/runtime/render/physics/input creation, mesh upload, material creation, five component registrations, and camera/light entities built field by field. Against 144 lines of actual game logic in `scripts/*.zig`. Thin scripts do not imply a thin host.

Note also what the Zig spike explicitly placed out of scope (its own header comment): TOML scene loading, on-screen text, audio, and scene routing — i.e. `ke_scene_loader`, `Font`/`Label`, `AudioPlayer`, `SceneRouter`. It did not eliminate that surface; it skipped it. Any claim that the spike proves the surface is unnecessary must account for that.

Where a machine-readable description of *the engine's own API* would help (Godot's `extension_api.json` pattern, a natural extension of what `scripts/generate_bindings.cs` already does) is in generating the C#-shaped layers — items 1 and 2 for the one language that actually needs them. That is a separate design question from this document.

---

## 13. Status & evidence

Two spikes ran back-to-back on `spike/zig-pong` (2 commits, +4868 lines, unmerged; the branch's merge-base is ~180 commits behind `main` and predates both the CMake→`build.zig` migration and the framework's C→Zig port, so it is reference material rather than a merge base):

- **Spike 1** (`examples/zig/games/pong/`): a full Pong recreation talking to the C ABI directly from Zig via `@cImport`, with a comptime `NodeType(T, name)` mechanism proving fields→component/hook→system collapse *within* Zig. This is the mechanism §2's middle-end generalizes.
- **Spike 2** (`src/zig/framework/node_host/`, `src/csharp/scripting/KernelEngine.Scripting/`, `examples/csharp/games/pong-inr-spike/`): the pipeline end-to-end in C#, headless. Observed: a `Player` entity's position advancing by exactly `speed × dt` per tick across 10 frames, driven entirely by a hand-written `OnUpdate` body, with zero `Toolkit` reference in the new projects, and every verifier-rejection case producing its documented error with nothing registered.

**What the spikes proved and what they didn't.** They proved the thesis: registration mechanics can be centralized natively, and a language needs only a thin SDK plus generated glue. They did not prove that serialization was necessary — that was assumed from the LLVM framing and is retracted in §9.2. The verification, transactionality, and per-segment dispatch results carry over unchanged to the builder design; only the input format changes.
