# Scripting Architecture V2 — the INR-driven node host

**Status**: Design locked at the level proven by two spikes (branch `spike/zig-pong`, both green). Native `ke_node_host` shape, INR v0 document shape, and the C# SDK/frontend split are validated end-to-end. Per-language frontends (scrapers), INR v1 hardening, and the production migration (Phases 1–4 below) are **not started**.

**Supersedes**: [`FrameworkArchitectureV2.md`](FrameworkArchitectureV2.md) §5 ("C# ergonomics layer — source generator + script safety model") as the mechanism for node-registration ergonomics. §5's `NodeBehavior`/`ref struct View`/fields-as-components **UX goals are not superseded** — they are still what a C# author should feel — but the mechanism realizing them changes: no per-language reimplementation of "fields → component, hooks → system", one native middle-end owns it. See §9 for the precise reconciliation.

**Audience**: Engine maintainer + future language-binding authors (C#, Python, Lua, …).

**Companion docs**: [`RuntimeArchitectureV2.md`](RuntimeArchitectureV2.md) §15 (script safety model — this design is a concrete implementation of its "single doorway" doctrine for the node-registration problem specifically). [`KernelArchitectureV2.md`](KernelArchitectureV2.md) §2 (tier criterion — placement rationale, §3 below). [`Kanban.md`](Kanban.md) Tier S (tracking; this doc is the authoritative design, Tier S is authoritative for scheduling/status).

---

## 1. The problem

Supporting a new scripting language today costs four things: (1) P/Invoke-style bindings — mechanical, irreducible; (2) hand-written wrapper ergonomics (C#'s `Node`/`NodeWorld` in `src/csharp/toolkit`); (3) a **per-language reimplementation of the same registration mechanics** — "a struct's fields become an ECS component, a lifecycle method becomes a system with an access-list" — today that's hand-written for the one language we have, and `FrameworkArchitectureV2.md` §5 planned to reimplement it a second time as a C# Roslyn source generator; (4) the semantics themselves, duplicated inside (2) and (3).

Item 3 is the one that scales badly: `O(mechanism-complexity × N languages)`. A Python binding would need its own metaclass-based version of "fields → component". A Lua binding would need its own metatable-based version. Every reimplementation is a place semantics can drift between languages — the exact failure mode the project is trying to avoid before committing to multi-language scripting (see `docs/EngineRoadmap.md` positioning Zig-community courting before C# scripting stabilizes).

**The question this design answers**: can the mechanism be written once, in Zig, and reused by every language — the way a compiler's optimizer is written once and reused by every front-end?

---

## 2. The architecture — literally front-end / middle-end / back-end

```
Player.cs (Jogo)  ──frontend scraper──►  Player.toml (INR)  ──┐
                                                                 │
                                                    ke_node_host │ (middle-end, Zig, native)
                                                    parses + VERIFIES the INR,
                                                    registers the node's own ECS
                                                    component (layout from [[field]]),
                                                    registers the runtime system
                                                    (access-list from [[component]]),
                                                    owns spawn(type_name)
                                                                 │
                                          bind_hook("Player","OnUpdate", fn) ◄── SDK backend leg
                                                                 │            (thin, per-language,
                                          per-segment dispatch ──┘             hand-written today)
                                                                 │
                                          Player.OnUpdate(...) ◄── user code, zero interop
```

Three roles, LLVM-style:

- **Frontend** (per language — **not built by either spike**, mandatory long-term): translates native syntax (`class Player : Node { float speed; void OnUpdate(...) }`) into an INR document. Owns *nothing* semantic — pure syntax → data translation. It is inadmissible for an author in any supported language to ever hand-write a line of Zig or edit an INR file by hand in the shipped product; the frontend runs automatically as a build step (Roslyn incremental generator for C#, a similar mechanism per language).
- **Middle-end** (`ke_node_host`, Zig, this design's deliverable, **proven**): consumes INR, verifies it, does every mechanical registration step once. This is the reusable part — the compiler's optimizer.
- **Back-end / SDK** (per language, thin, **proven for C# only**): a small hand-written library (`KernelEngine.Scripting`, ~150 LoC) giving the language a `Node` base class to compile against, plus the runtime glue (`NodeHost` wrapper, the native↔managed hook trampoline). Distinct from the frontend: the SDK is compiled once and shipped; the frontend runs per-project at build time.

LLVM lessons this design deliberately encodes:
1. **The IR is a serialized artifact**, not an in-memory language-specific type — INR is a TOML *document*, so any frontend in any language can emit it; nothing requires recompiling a Zig program per schema (an earlier, abandoned version of this spike required exactly that — see §9.1).
2. **Frontends lower, they never own semantics** — a scraper's only job is syntax → INR translation. All meaning (what a valid field type is, what an access string means, how a hook maps to a phase) lives in the middle-end's verifier, so languages structurally cannot drift from each other.
3. **A verification pass runs before any registration** — a bad INR document (unknown field type, unresolvable component reference, malformed access string) fails the whole `load()` with a descriptive `ke_error` and registers nothing. Half-registered node types are not a representable failure mode.
4. **The same IR serves AOT and (future) JIT paths** — a static language's frontend runs at build time; nothing in the design prevents a dynamic language from emitting INR at load time and calling `load()` live.

---

## 3. Where this lives — kernel-doctrine placement

Per `KernelArchitectureV2.md` §2's tier criterion (*"does the scheduler or the ECS need this to run a system?"*), `ke_node_host` is **not** kernel substrate — the scheduler and ECS run perfectly well without it. It is a **Tier 3 domain / framework concept**, the same tier as `ke_scene_tree` and `ke_scene_loader`: a policy layer built *on top of* `ke_ecs`+`ke_runtime`, offering a higher-level convenience no execution path requires.

Concretely, mirroring the existing framework-domain shape:

- **Contract** (vtable only, no policy): `src/c/framework/include/kernel_engine/framework/node_host.h`.
- **Impl** (Zig, one concrete implementation today): `src/zig/framework/node_host/`, following the `src/zig/configuration/toml/` precedent exactly — vendored `third_party/tomlc99` (own independent copy, per the vendoring doctrine: `src/c/framework`, `src/zig/configuration/toml`, and `src/zig/framework/node_host` each vendor their own copy, none reaches into another), `build.zig` + `CMakeLists.txt` producing a `SHARED IMPORTED` CMake target, factory header `node_host_create.h` (`ke_node_host_create(ke_ecs*, ke_runtime*, ke_error**)`, both borrowed).
- **Bindings**: regenerated via `scripts/generate_bindings.py` from a `.rsp` (pinned rule: never hand-write bindings) — `src/csharp/scripting/KernelEngine.Scripting/Native/NodeHost.rsp` in the spike, following the exact `--remap`/`--exclude`/`--with-using` conventions every other `.rsp` in the repo uses.

This placement means a hypothetical second ECS/runtime implementation (a future custom storage backend, per `RuntimeArchitectureV2.md` §8's "our scheduler, flecs storage-only" split) does not need its own node-host reimplementation — `ke_node_host` depends only on the `ke_ecs`/`ke_runtime` contracts, not on flecs or the enkiTS-backed scheduler specifically.

---

## 4. INR v0 — the type-side IR

TOML (PO decision, consistent with `.scene` files already being TOML — see §8 for how the two relate and *don't* collide). One node type per document today; the middle-end supports loading multiple documents into one host (`load()` is additive, guarded against duplicate type names).

```toml
[node]
name = "Player"

[[field]]           # → the node's own component; layout = declaration order,
name = "speed"       #   C alignment rules (matches every other ke_* component's
type = "f32"         #   layout convention — no ABI surprises for a native reader).
                      #   v0 types: f32, f64, i32, u32, i64, u64, bool.

[[field]]
name = "health"
type = "i32"

[[hook]]             # v0: only "OnUpdate" is recognized, maps to KE_PHASE_UPDATE.
name = "OnUpdate"    # An unrecognized hook name is a load() error (KE_ERROR_NOT_SUPPORTED),
                      # not a silent no-op — see §5's "fail loud" principle.

[[component]]        # The access-list for OnUpdate's backing system, resolved by ECS
name = "position"    # component name at load() time. External components (like
access = "RW"        # "position" here) must already be registered on the ecs —
                      # load() fails with KE_ERROR_NOT_FOUND otherwise.

[[component]]        # A [[component]] entry matching [node].name refers to the
name = "Player"       # node's own component (auto-registered from [[field]]) —
access = "RW"        # this is how a hook declares it touches its own data.
```

**Verifier rules (all enforced before any `component_register`/`register_system` call — see `src/zig/framework/node_host/src/node_host.zig`'s `vtLoad`)**:
- `[node].name` required, must not already be loaded on this host.
- At least one `[[field]]`; every field's `type` must be in the v0 type table (unknown type → `KE_ERROR_INVALID_ARGUMENT` naming the field and the bad type).
- Every `[[hook]].name` must be a v0-recognized hook (today: `OnUpdate` only).
- Every `[[component]].name` either equals `[node].name` (self-reference, resolved to the just-registered own component) or must already exist on the `ke_ecs` (`component_lookup` failure → `KE_ERROR_NOT_FOUND` naming the missing component).
- Every `[[component]].access` must be exactly `R`, `W`, or `RW` (anything else → `KE_ERROR_INVALID_ARGUMENT` with the offending string echoed).
- `[[component]]` count is capped at `KE_QUERY_MAX_TERMS` (the existing engine-wide query-term limit, `runtime.h`) — exceeding it is a load() error, not silent truncation.

Verified by the spike (`examples/csharp/games/pong-inr-spike`, run against hand-crafted bad documents): each violation above produces the exact error message quoted, and the node type is *not* partially registered.

---

## 5. `ke_node_host` contract

```c
typedef void (*ke_node_hook_fn)(void *ctx, const ke_entity *entities,
                                void *const *columns, size_t count, float dt);

typedef struct ke_node_host {
    void *handle;
    bool      (*load)(self, const char *inr_toml_text, ke_error **);
    bool      (*bind_hook)(self, const char *node_type, const char *hook,
                           ke_node_hook_fn fn, void *ctx, ke_error **);
    ke_entity (*spawn)(self, const char *node_type, ke_error **);
} ke_node_host;  // + ke_node_host_handle{ref, destroy}
```

- **`load`**: parse + verify + register, as above. Idempotent per node-type-name (a second `load()` of the same name is a hard error, not a silent replace — this is intentional: hot-reload semantics for INR are an explicit open question, §7).
- **`bind_hook`**: registers the backing `ke_runtime` system. `columns[i]` order at dispatch time = the INR's `[[component]]` declaration order — the SDK, which parsed (or, for a frontend-driven language, emitted) the same INR, knows this order and casts each column to its blittable mirror type. **Dispatch granularity is one call per archetype segment, not per entity** — this is the load-bearing performance decision: a managed language pays one native→managed transition per segment (potentially hundreds of entities), not per entity. Internally this is implemented as one `ke_runtime` system per hook, whose native `execute` callback (`hookTrampoline` in the impl) walks `ke_system_ctx_view` per `RuntimeArchitectureV2.md` §15's "single doorway" doctrine and calls the bound `ke_node_hook_fn` once per resolved segment.
- **`spawn`**: creates an entity carrying every component the node type declares (zero-initialized). The caller (SDK/game code) is responsible for setting initial field values after spawn — `spawn` is deliberately dumb (no INR-side "default" value support in v0, see §7).

**Fail-loud discipline** (per project doctrine — no assert/abort, `ke_error` everywhere): every failure path in `node_host.zig` returns `false`/`KE_ENTITY_INVALID` with a `KE_ERROR_SET`-equivalent populated error, never a partial success. This was exercised directly by the spike's verifier tests (§4).

---

## 6. The C# SDK/frontend split (proven)

**SDK** (`src/csharp/scripting/KernelEngine.Scripting/`, ships once, hand-written, ~150 LoC total):
- `Node` — abstract base, holds `Entity` identity. Exists purely so `class Player : Node` is a valid, recognizable declaration for the (future) frontend scraper to find.
- `NodeHost` — managed wrapper over `ke_node_host`: `Load(string)`, `BindHook(string, string, NodeHookDispatcher)`, `Spawn(string)`, plus the `[UnmanagedCallersOnly]` trampoline and `GCHandle`-pinned dispatcher lifetime management.

**Frontend output** (per node type, **hand-written in the spike, meant to be scraper-emitted in production** — every file below is explicitly marked with a comment saying so):
- `Player.toml` — the INR document (§4).
- `Player.g.cs` — the *generated glue*: a blittable mirror struct per external `[[component]]` reference (`Position`), a mirror struct of the node's own fields (`Player.Data`), and a `Register(NodeHost)` static method wiring `BindHook` with a dispatcher that walks the segment, materializes/reuses a managed `Player` instance per entity (currently a `Dictionary<ulong, Player>` — see §7's perf note), copies field values in, calls the user's hook method, copies them back out.

**User code** (`Player.cs`, what an author actually writes): plain C# fields + hook method bodies. Zero `unsafe`, zero interop attributes, zero ECS API calls — the exact ergonomics bar `FrameworkArchitectureV2.md` §5 was aiming for, just reached by a different mechanism (§9).

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

**Composition root** (`Program.cs`, headless in the spike): creates `ke_ecs`/`ke_scheduler`/`ke_runtime` via the existing generated bindings (`KernelEngine.Ecs.Flecs`, `KernelEngine.Scheduler.Enki`, `KernelEngine.Runtime`) exactly as the C/Zig examples' `main()` do, then `NodeHost.Create(ecs, runtime)`, `Load`, `Register`, `Spawn`, tick loop. **Zero reference to `KernelEngine.Toolkit`** — verified by `grep -r Toolkit` over the spike's new projects returning only prose comments, no `ProjectReference`s.

---

## 7. Known gaps and honest limitations (carried forward, not hidden)

- **Property-bag interop with scenes is not wired.** The node's own component is registered via plain `component_register(name, size)` — no `ke_component_field` metadata. This means the *existing* scene-loader property-apply path (`ke_ecs_component_apply_variant`, used by `[entity.components.paddle] move_action = "..."` in `.scene` files today) cannot yet target an INR-declared component. Fixing this means switching to `component_register_v3` and deriving `ke_component_field[]` from the INR's `[[field]]` list — mechanical, not started.
- **One hook (`OnUpdate`) only.** `OnBind`/`OnReady`/`OnUnbind` (the C# `Node` lifecycle today) aren't in the v0 INR vocabulary. Extending the hook table and the phase-mapping (`OnUpdate → KE_PHASE_UPDATE`, future hooks → `KE_PHASE_STARTUP`/`KE_PHASE_SHUTDOWN`/none-at-all-for-OnBind-which-runs-at-spawn) is additive, not a redesign.
- **No hot-reload semantics.** A second `load()` of an already-loaded type name is a hard error. Whether re-`load()` should replace-and-migrate live entities is an open question (§ below), deliberately deferred rather than guessed at.
- **Per-instance managed overhead in the C# glue.** The `Dictionary<ulong, Player>` lookup-or-create per segment row is adequate for a spike, wrong for production: a scraper-emitted glue should index by a dense per-archetype row position (matching how `ke_ecs_segment` already hands back contiguous columns) instead of hashing entity IDs. Flagged for the production frontend, not fixed here — fixing it in hand-written glue would be optimizing throwaway code.
- **No array/nested-struct field types.** v0's field table is scalars only (§4). A `Vector3`-shaped field needs either a native `vec3` INR type or a documented "three f32 fields" convention — undecided.
- **`ke_node_host` doesn't (yet) plug into `ke_scene_loader`.** See §8 — this is a known, deliberate seam, not an oversight.

---

## 8. Relationship to scenes — types vs. instances

`examples/csharp/games/pong/scenes/*.scene` are **instance data** (which entities exist, at what transform, with what property overrides) parsed by `src/c/framework/src/scene_loader.c`. INR documents are **type data** (what fields/hooks/access a node type has). Both are TOML; they are not the same schema and must never be confused.

The convergence point, **not wired in this design, contract kept compatible for it**: `scene_loader.c`'s `dispatch_script` (line ~232) calls one globally-registered `ke_script_factory_func(ctx, entity, type_name, out_error)` whenever a scene entity has `type = "Pong.Ball"`. `ke_node_host` could *be* that factory: on seeing `type_name`, look it up among loaded INR types and `spawn`-equivalent the declared components onto the already-created `entity` (scene_loader creates the entity; node_host would need a variant of `spawn` that attaches to an existing entity rather than creating a new one — a small, additive contract change). This is intentionally left as a Phase 1 item (§10) rather than guessed at now, because it changes `spawn`'s contract shape and deserves its own validation pass.

---

## 9. Reconciliation with the existing Roslyn source-gen plan

`FrameworkArchitectureV2.md` §5 planned a five-phase Roslyn source generator (`[SceneNode]` discovery → `ref struct View` → `NodeBehavior` → fields-as-components → AOT analyzer) that would **own** the fields→component/hook→system mechanism itself, emitting C#-specific runtime registration code with no native counterpart. That plan is superseded as the *mechanism* — building it would mean C# owns its own copy of exactly the logic this design centralizes in `ke_node_host`, reintroducing the per-language duplication problem for the very first language.

**What carries forward unchanged**: the UX bar. `NodeBehavior`, fields-that-feel-like-fields, the `ref struct View` funnel's compile-time enforcement that component access can't escape the stack — all still describe what a C# author should experience. The reconciled shape: a Roslyn `IIncrementalGenerator` becomes the **frontend** (§2) — it reads `class Player : Node { [Field] float speed; void OnUpdate(...) }`-shaped source and emits `Player.toml` + `Player.g.cs` (the glue shown hand-written in §6), i.e. it automates exactly the two files the spike hand-wrote, using the incremental-generator infrastructure §5.2 already scoped. It does **not** independently decide what a valid field type is or how access is inferred — `ke_node_host`'s verifier is the single source of truth for that, shared with every other language's frontend.

**§9.1 — the abandoned first design, for the record**: an earlier version of this spike had Zig comptime *emit* C# directly (`nodegen --backend csharp`, a schema authored as a Zig struct compiled into the generator). It was abandoned mid-session when the PO inverted the architecture: Zig comptime reflection resolves at the *reflecting program's own compile time*, so "schema in Zig" would have required rebuilding the generator per schema and never let a schema be produced by a non-Zig frontend — precisely the constraint LLVM lesson #1 (§2) rules out. The INR-as-serialized-document design is the correction.

---

## 10. Implementation plan — spike to production

1. **INR v1 hardening** (native, no new language work): full hook table (`OnBind`/`OnReady`/`OnUnbind`) + phase mapping; `component_register_v3` + `ke_component_field` derivation so scene-authored properties can target INR components (§7); a fuzz/negative-test corpus for the verifier as a proper native test target (today's verifier coverage is the three ad-hoc cases run manually in the spike).
2. **`ke_node_host` as an optional `ke_scene_loader` script factory** (§8): the `spawn`-onto-existing-entity contract variant, wired so `.scene` files can reference INR-declared types by name exactly like they reference hand-registered C# node types today. Validates the "types vs instances" seam for real instead of by inspection.
3. **C# frontend** (Roslyn `IIncrementalGenerator`, per §9): automates `Player.toml` + `Player.g.cs` emission from `class Player : Node` declarations, using `FrameworkArchitectureV2.md` §5.2's already-scoped incremental-generator project setup. Retire the spike's hand-written glue once this lands.
4. **Pong (or a comparable real game) fully on this pipeline in C#**, replacing hand-written `Toolkit` node scripts for new/ported content — not a big-bang rewrite of `Toolkit` itself (per project doctrine, incremental migration; `Toolkit` content migrates opportunistically, not on a deadline).
5. **A second language** (Python or Lua — whichever the roadmap prioritizes) gets a frontend + SDK. **This is the actual test of the thesis**: if step 5 costs "one frontend + one ~150-LoC SDK" and zero native changes, `O(1)` is proven in production, not just by construction in a spike.
6. **INR extensions as real games demand them**: array/nested field types, multiple hooks per node, hot-reload semantics (open question below), perf work on the reference C# glue's per-entity dispatch (§7).

---

## 11. Open questions

- **Hot reload**: does re-`load()`-ing a changed INR document replace the type definition and migrate already-spawned entities, or is it rejected? No answer yet — deferred until a language/workflow forces the decision (mirrors `RuntimeArchitectureV2.md`'s general pattern of not speculatively designing hot-reload before a concrete need).
- **Field defaults**: should `[[field]]` support a `default = ...` INR key so `spawn` can zero-init to something other than zero? Not needed by the spike; likely needed once a real game ships.
- **Multi-node INR documents**: v0 is one node type per document. Whether a game wants one file per type (current) or a directory of types loaded as a batch is a workflow question, not an architecture one — either is representable through repeated `load()` calls.
- **INR type-table extensibility**: v0's scalar-only field table (§4/§7) will need vectors/quaternions/strings/handles eventually; whether that's native INR types or a documented composition convention (e.g. "a `vec3` field is three `f32` [[field]] entries with a naming convention") is undecided.
- **Does a dynamic language (Python) actually want AOT frontend-at-build-time, or does it want to emit INR and call `load()` at process start?** Both are representable (LLVM lesson #4, §2); which one Python's binding should default to is a design question for when that binding is actually built.

## 12. Non-goals (explicit)

Python/Lua SDKs (until a language is actually prioritized). Replacing the existing ClangSharp-generated low-level P/Invoke bindings (`KernelEngine.*.Native` projects) — those remain the substrate `ke_node_host`'s own bindings and every composition root sit on. Multi-threaded hook dispatch beyond what `ke_runtime`'s existing wave scheduler already provides (node_host adds no new parallelism model — it rides the runtime's). A GUI/editor authoring surface for INR — it's a build artifact, not something a human is expected to hand-edit in the shipped product.

---

## 13. Status & evidence

Two spikes ran back-to-back on `spike/zig-pong` (worktree `.claude/worktrees/spike-zig-pong`):

- **Spike 1** (`examples/zig/games/pong/`): a full Pong recreation talking to the C ABI directly from Zig via `@cImport`, with a comptime `NodeType(T, name)` mechanism (`node.zig`) proving fields→component/hook→system collapse *within* Zig. This is the mechanism §2's middle-end generalizes.
- **Spike 2 / M1** (`examples/csharp/games/pong-inr-spike/`, `src/zig/framework/node_host/`, `src/csharp/scripting/KernelEngine.Scripting/`): the INR pipeline end-to-end in C#, headless. Ran and observed: a `Player` entity's position advancing by exactly `speed × dt` per tick across 10 frames, driven entirely by the user's hand-written `OnUpdate` body, with zero `Toolkit` reference anywhere in the new projects, and all three verifier-rejection cases (§4) producing the documented error messages with nothing registered.

M2 (a full Pong recreation in C# on this pipeline, per Implementation Plan step 4) was explicitly **not** run — the PO judged M1 sufficient to prove the mechanism and asked to consolidate into this document instead.
