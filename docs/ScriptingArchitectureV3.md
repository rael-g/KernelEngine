# Scripting Architecture V3 — making a new language cheap

**Status**: Strategy. No track below is started. Supersedes [`ScriptingArchitectureV2.md`](ScriptingArchitectureV2.md), which is retained only as the record of two rejected designs (§9.1 Zig-comptime codegen, §9.2 the INR serialized IR) and of the two spikes on `spike/zig-pong`.

**Audience**: Engine maintainer + future language-binding authors.

---

## 0. The rule everything derives from

> **Game code is written natively in the target language. The FFI is never part of what a game author sees.**

A C# author writes no `unsafe`, no `fixed`, no pointer. A Zig author writes `try physics.createBody(.dynamic, pos)` — error unions, real enums, slices, `defer` — not `physics.*.create_body.?(physics, c.KE_BODY_TYPE_DYNAMIC, x, y, null)`. A Lua author writes `input:isKeyDown "space"`, not `ffi.C.ke_input_snapshot_is_key_down(snap, 65)`.

**This rule is the constraint; everything below is a consequence of it.** Without it there is no work to do at all: every language already reaches the C ABI somehow, so "it can call the engine" is never the problem. The problem is that calling the engine *the way the ABI is shaped* is idiomatic in no language.

The counter-example is already in the repo. The Zig spike (`spike/zig-pong`) talks to the ABI directly, and it reads like this:

```zig
const t: *c.ke_transform_component = @ptrCast(@alignCast(
    ecs.ref.*.component_add.?(ecs.ref, cam, transform_cid).?));
```

That is C with Zig syntax. It compiles, it runs, and it is not what a Zig game author should ever write. **The spike is evidence for this rule, not against it** — it shows that raw FFI is unacceptable even in the language closest to C.

---

## 1. The goal, stated so it can be falsified

> **Adding a new scripting language should cost one backend — a closed set of rendering decisions (§6.2) — plus a runtime shim, and zero engine changes.**

The success metric is **hand-written lines per language**, not total lines. Generated code is close to free; hand-written code is what must be designed, reviewed, kept in sync, and debugged when it drifts from the language next door.

**Acceptance test** — the only one that matters: write a real game in a second language, in that language's own idiom (§0). If it costs one backend (§6.2's seven decisions) plus a runtime shim, with no per-domain hand-written wrapper, the strategy worked. If it requires hand-writing a `Camera` class, a `Font` class, or a mesh-primitive helper, it did not — and each such helper names a Track 1 gap.

Writing a game is also the *cheapest way to enumerate Track 1 gaps*: an author hits a wall exactly where a capability is trapped above the ABI, and the walls arrive ordered by real usage rather than by audit sweep.

### 1.1 Measured baseline (C#, today)

| | LoC |
|---|---|
| Generated (`src/csharp/*/Native/Generated/`) | 3 801 |
| Hand-written — code | **5 195** |
| Hand-written — XML doc comments | 1 793 |
| Hand-written — blank | 994 |
| Hand-written total | 7 982 |

(`src/csharp/cli` excluded — tooling, not a binding.) The 1 793 doc lines have no generable source today: header doc coverage is uneven and mostly absent — `input.h` and `event.h` carry `/** @brief */` blocks, while `ke_ecs.h` and `scene_tree.h` carry none at all.

**Target**: **zero hand-written lines per domain**. That is the number that matters — it is what scales with the engine's API surface and multiplies by language. The per-language floor (§9) is a separate, smaller, non-growing constant.

---

## 2. The governing insight — the ABI's shape is idiomatic nowhere

> **Error by out-parameter, raw pointers, integer-typed enums, pointer+count pairs, manual destroy: this shape is idiomatic in no language, C included.** Every target needs the same *set* of transformations, applied in its own idiom.

What differs per language is not *whether* the layer is needed — it is how the layer renders. The transformation rules are shared:

| Shared classification | C# | Zig | Lua | Python |
|---|---|---|---|---|
| slot is **fallible** | `throw` | error union + `try` | `error()` | `raise` |
| value is **owned** | `IDisposable` | `defer deinit` | `__gc` | `__exit__` |
| params are **one sequence** | `Span<T>` | slice | table | buffer |
| int is an **enum** | `enum` | `enum` | string constant | `IntEnum` |
| vtable is a **callback** | `[UnmanagedCallersOnly]` + `GCHandle` | closure + context ptr | registry ref | `ctypes.CFUNCTYPE` |

**Two earlier claims in this document were wrong and are withdrawn:**

- *"Zig/Lua/Python cost ≈ 0 wrapper."* That measured **FFI reach** — can the language call C at all — not idiom. Under §0 the answer is different: they all need a comparable idiomatic layer. Zig's `@cImport` buys it nothing here.
- *"C# is the worst case, not the template."* Half wrong. C# is the worst case for **bindings** (3 801 generated lines, because it cannot ingest C headers). It is **not** an outlier for the idiomatic layer, which every language needs equally.

The corrected reading of the C# baseline (§1.1) follows: those 5 195 lines were **not bloat**. They are roughly the right amount of idiom for one language. The defect was never their size — it was that they were written by hand instead of derived.

This makes `kabic`'s justification stronger, not weaker: it is not a way to shrink C#, it is **the only way to give any language a native feel without O(N) hand-written work**.

---

## 3. The invariant

Everything in this document serves one two-clause invariant:

> **(A) Every engine capability is reachable through the C ABI.**
> **(B) Everything in the C ABI is machine-describable.**

Clause A fails today: engine functionality lives *above* the ABI, in C#, where no other language can reach it (§4). Clause B fails today: the headers carry syntax but not semantics, so `kabic` cannot produce an idiomatic layer (§5).

Restore both clauses and the per-language cost collapses to generation. Restore only one and it does not: describing an incomplete ABI generates bindings to a subset, and completing an undescribable ABI still requires hand-writing the wrappers.

---

## 4. Track 1 — Completeness: no engine functionality above the ABI

**This is a hard prerequisite, not a parallel concern.** A domain cannot be annotated, described, or generated until its ABI is settled, because generating a binding for a surface that is about to move is rework. Track 1 gates Track 2 *per domain*.

**Problem.** Capabilities have leaked into the C# layer. Confirmed instances:

- `Render.Abstractions/MeshPrimitives.cs` (115 LoC) — builds quad / plane / cube vertex and index data in C#, `stackalloc MeshVertex[24]` and a `Face()` helper. Reason the Zig spike hardcoded its own quad vertices in `main.zig`: this primitive is unreachable from any language but C#.
- `Render.Webgpu/WebgpuRenderModule.cs` (331 LoC) — reads `[render] cluster_grid_x/y/z`, `max_lights_per_cluster`, `clear_color_*` and decides fallback defaults, in C#, despite `ke_configuration` being a native service.
- `Toolkit/Systems/LabelUiSystem.cs` — a runtime **system** implemented in C#.
- `Toolkit/Scene/SceneRouter.cs` + `SceneRouterModule.cs` — scene state machine.
- `Toolkit/Input/InputActionMap.cs`, `Text/Font.cs` + `Label.cs`, `Assets/ModelExtensions.cs`.

Each is a capability a Lua or Python game would not inherit and would have to reimplement — the exact `O(N)` duplication the whole effort exists to avoid.

**Principle.** *If two languages would both want it, it belongs below the ABI.* A managed layer is allowed to hold: language-idiom adaptation, the DI/composition idiom, and language-runtime plumbing. Nothing else.

### 4.1 Audit rubric

Every hand-written file in a domain gets exactly one verdict:

| Verdict | Test | Action |
|---|---|---|
| **MECHANICAL** | It only forwards to a vtable slot, adapting types and errors. | Leave it; Track 3 will generate it and delete this file. |
| **LEAKED** | It computes, decides, or stores something. A Lua game would need it and could not get it. | Move below the ABI. Blocks the domain. |
| **IDIOM** | It exists only because of how this language expresses things (DI, `IDisposable`, `Span`, exceptions). | Keep, and confirm it is in the §9 floor. |
| **DEAD** | Nothing references it, or it duplicates another file. | Delete. |

The discriminating question for MECHANICAL vs LEAKED is **"if I deleted this, would the engine lose a capability, or only C# lose a convenience?"** Losing a capability means LEAKED.

**Judge by behaviour, not by size.** A file that only reads fields can still be LEAKED if it *computes* — decoding a bitset, deriving a matrix, interpreting a discriminator. Ask literally: **does this compute, decide, or store anything?** A thin-looking file that answers yes is LEAKED. Appendix A.1 records a case where judging by shape got this wrong.

**Encoding knowledge is the most common leak.** Whenever the managed side reimplements how a native value is *laid out* — bit offsets, packed fields, discriminator conventions documented only in prose — that is LEAKED, and the fix is an ABI accessor, not an annotation. Publishing an encoding via a tag makes every language replicate it; moving it below the ABI deletes it everywhere.

Worked example of a move-down: `MeshPrimitives.Quad()` becomes `ke_render_service.create_primitive(KE_PRIMITIVE_QUAD)` — the C# side drops from 115 hand-written lines to one generated call, and every other language gets the primitive for free.

Worked example of the MECHANICAL/IDIOM boundary, from the audit in Appendix A.1: `Input.cs`'s `DrainEvents(Span<InputEvent>)` reshapes the flat native `ke_input_event` into a `Kind`-discriminated union. It looks LEAKED at first glance — ~45 lines another language would redo — but the native type is already flat and complete, so the reshape adds accessors, not capability. **IDIOM.** The test that settles it is the one above: deleting it costs C# a convenience, not the engine a capability.

### 4.2 Deliverable

Per domain: an audit table with one verdict per file, and for every LEAKED verdict either a landed native change or an explicit deferral recorded with its reason. A domain is **not** cleared for Track 2 while an unresolved LEAKED verdict remains in it.

---

## 5. Track 2 — Describability: annotate the ABI, emit a description

**Problem.** The headers carry types but not meaning. `kabic` sees `const char*` and cannot know it is borrowed UTF-8; sees `float*` and cannot know it is four floats (this exact gap already produced a real defect — a `const float base_color[4]` parameter lowered to a scalar `float` in generated bindings); sees `int` and cannot know it is a `ke_key`; sees `ke_entity*` next to `size_t count` and cannot know they are paired.

### 5.1 Attribute-based annotation does not work here — measured

The obvious approach is a macro expanding to `__attribute__((annotate(...)))` per parameter. **It is unusable for this ABI, and the reason is structural.** Measured against `zig cc -Xclang -ast-dump=json` on the real toolchain:

| Placement | Attribute survives in the AST? |
|---|---|
| Parameter of a plain function declaration | ✅ |
| Struct field | ✅ |
| **Parameter of a function-pointer field** | ❌ **dropped** |
| **Parameter of a function-type `typedef`** | ❌ **dropped** |

A parameter of a function *type* is not a declaration, so clang does not retain attributes on it. **Every public slot in this engine is a function-pointer field in a vtable struct** — precisely the shape where it fails. Annotating the whole slot with one packed string works, but degrades into a stringly-typed mini-DSL with no compiler check that its parameter names still match the signature.

**No new annotation macros are introduced.** The vocabulary sketched in earlier drafts of this section is withdrawn.

### 5.2 Doc comments carry both documentation and semantics — one artifact

Doc comments **do** survive on vtable fields, and clang's built-in Doxygen parser emits them as structured, per-parameter nodes. Measured on the same header shape:

```c
typedef struct ke_input_actions {
    /**
     * Loads action bindings from a `.input` file, clearing previous actions.
     * @param path      [borrowed,utf8] Filesystem path to the bindings file.
     * @param out_error [out,nullable,owned]
     * @return false on parse failure.
     */
    bool (*load)(struct ke_input_actions *self, const char *path, ke_error **out_error);
} ke_input_actions;
```

`zig cc -Xclang -ast-dump=json -fparse-all-comments` returns each `@param` as its own node, bound to its parameter name, with the bracketed tag text intact and available for extraction.

This collapses two problems into one artifact:

- The 1 793 lines of C# XML doc, which are C#-only today and have **no** generable source (the headers currently carry zero structured doc comments), become the source for every language's generated documentation.
- The semantic tags ride in the same comment block, attached per parameter, next to the contract.

**Convention over annotation.** Most of the ABI needs no tags at all, because the project's doctrine already carries the semantics: `bool` + `ke_error**` means "fallible, throw on false"; `ke_X_handle{ref, destroy}` means "owned, `IDisposable`"; `_params` structs are input bags; `ke_<domain>_<verb>` gives the method name. Tags are only needed for what the C type genuinely cannot express — fixed-size arrays, `T*`+`count` pairs, string encoding and lifetime, nullability, and integer-typed enums. Expect them on a minority of parameters.

**No sidecar file.** The description is derived, never authored — the same discipline that rejected the INR.

### 5.3 `ke_api.json` — a build output, never an input

The extraction pipeline, with **zero new dependencies**:

```
public headers (annotated doc comments)
   │  zig cc -Xclang -ast-dump=json -fparse-all-comments      ← zig cc IS clang; already the toolchain
   ▼
clang AST JSON
   │  extractor (scripts/, matching the existing dotnet-run script precedent)
   ▼
ke_api.json          ← committed, drift-checked
   │
   ├─► CSharpBackend  ─► idiomatic managed layer
   ├─► Lua / Python  ─► loaded at runtime (§6.2)
   └─► doc site
```

`ke_api.json` carries every vtable, slot, parameter with its tags and docs, struct, enum, constant, factory, and handle type. **It is a build artifact, regenerated from headers, never hand-edited** — the same rule that already governs `Native/Generated/`. A drift check (precedent: `scripts/check_bindings_drift.cs`) fails the build when it disagrees with the headers.

**This removes the ClangSharp dependency rather than adding to it.** ClangSharp exists today to parse headers; `zig cc -ast-dump=json` does the same job with a compiler the build already requires, no libclang NuGet and no `dotnet tool restore` in the native path. See §6.3.

This mirrors Godot's `extension_api.json`, with one deliberate simplification: **Godot's description exists to support dynamic dispatch by name at runtime** (`ClassDB`, method binds, hashes), because GDScript resolves calls live. Our vtables are static and known at build time, so the description carries types and semantics but needs **no runtime registry, no method hashes, no name-based dispatch**. Strictly less machinery than Godot, not more.

### 5.4 Worked example — what `kabic` produces

From the annotated slot in §5.2, `CSharpBackend` emits what `Framework/Input/NativeInputActions.cs` writes by hand today:

```csharp
/// <summary>Loads action bindings from a `.input` file, clearing previous actions.</summary>
/// <param name="path">Filesystem path to the bindings file.</param>
/// <exception cref="KernelError">Parse failure.</exception>
public void Load(string path)
{
    ke_error* err = null;
    fixed (byte* p = Encoding.UTF8.GetBytes(path + "\0"))
        if (!_native->load(_native, (sbyte*)p, &err))
            throw KernelError.FromNative(err, "load");
}
```

Note how little of this needed a tag: the exception translation, the handle deref, and the method name all come from doctrine convention. Only `[utf8]` on `path` was not inferable.

### 5.5 End-to-end proof — measured on `ke_input`

The full pipeline was run against an annotated copy of `src/c/input/kernel_engine/input/input.h`, producing `ke_api.json` and a generated C# wrapper, compared against the hand-written `src/csharp/input/KernelEngine.Input/Input.cs` (130 lines).

| Member | Result |
|---|---|
| `Update()`, `GetSnapshot()`, `Dispose()` | Generated, equivalent to hand-written |
| `IsKeyDown()` | Generated **better** — typed `Key` parameter |
| `IsKeyPressed()` | Generated — **the hand-written wrapper does not expose it at all** |
| `DrainEvents(Span<ke_input_event>)` | Generated — pointer+count pair collapsed into one `Span` |
| `DrainEvents(Span<InputEvent>)` translation | Not generated — LEAKED (§4.1) |
| `CaptureSnapshot() → IInputReader` | Not generated — IDIOM |

Roughly 70 of 130 lines generated. Only three tags were needed across the whole vtable — `[enum:ke_key]`, `[out]`, `[out,array_of:capacity]`; everything else came from convention.

**Two findings that matter more than the ratio:**

1. **The generated wrapper is better than the hand-written one.** `Input.cs` declares `IsKeyDown(int key)` — the fact that the value is a `ke_key` was lost in hand translation. And `is_key_pressed` exists in the ABI but is silently absent from the managed surface. Hand-written wrappers lose both type information and ABI surface, and nothing detects it.
2. **Tag drift fails the build.** Because parameter names are recovered by slicing the declaration clang validated (§5.3), `kabic`'s frontend can check that each `@param` names a real parameter. Renaming a parameter without updating its tag produces:
   ```
   ERROR: ke_input.is_key_down: @param 'keyy' is not a parameter (signature has ['key'])
   ```
   An annotation that rots breaks the build instead of silently generating a wrong binding.

**Caveats.** The §5.5 prototype was a throwaway script; the production version is `kabic` itself (§8.2). Early versions did not yet emit factories/constructors, structs, or enums, and the type map was incomplete — implementation gaps, not mechanism gaps; the mechanism itself is proven.

---

## 6. Track 3 — `kabic`: shared classification + per-language backend

**Naming it.** What Track 3 builds is not a generator — a generator takes input and emits code. This parses (§5.3's clang AST dump), performs semantic analysis (§5.3's `@param`-vs-signature validation, which fails the build on mismatch rather than emitting silently), classifies (§6.1, below), and only then emits, per target. That shape — frontend, semantic model, analysis, per-target codegen — is a compiler's, and it earns a name the way `ke_node_host` or `kerror` did rather than staying "the generator" across a dozen inconsistent mentions. Named **`kabic`** (Kernel ABI Compiler): `scripts/extract_api.cs` is its frontend, `ke_api.json` its IR, `Classifier` its semantic-analysis pass, and each `*Backend` (`CSharpBackend` today) one of its targets — the same relationship `clang`/LLVM have to their passes and backends. Calibrate the analogy honestly: no optimization passes, no multi-stage IR, and today's verifier checks one thing (parameter-name/tag agreement) — a compiler in shape, not yet in sophistication.

`kabic` is **not one generator-shaped blob**. It splits at a seam that §2 makes obvious: deciding *what a slot means* is language-independent; deciding *how to say it* is not.

```
headers ──► extract_api.cs ──► ke_api.json ──► Classifier ──┬──► CSharpBackend
 (§5)         (frontend)         (IR:            (semantic  │──► LuaBackend
                                  description)     analysis)  │──► PythonBackend
                                                    fallible / └──► ZigBackend
                                                    owned /
                                                    sequence /
                                                    callback /
                                                    enum
```

### 6.1 The shared middle — classification

From the description alone, every slot is classified before any language is considered:

- trailing `ke_error**` with a `bool` return ⇒ **fallible**; the error parameter leaves the public signature
- `ke_X_handle{ref, destroy}` ⇒ **owned**; needs a lifetime idiom
- a sole `[out]` parameter ⇒ **a return value**, not a parameter
- `[out, array_of:count]` ⇒ pointer and count are **one sequence**
- `[enum:T]` ⇒ an integer that is really an enumeration
- a vtable passed **by value** into a slot ⇒ a **callback interface** the caller implements

None of that mentions a language. It is written once.

**The seam is not serialized.** The semantic model is an in-process pass over `ke_api.json`, not a second file — it crosses no boundary, and the discipline holds: serialize only what does. Dump it for debugging; never author it.

### 6.2 The per-language backend — rendering

A backend is a closed set of decisions, which is what makes a new language *bounded* rather than open-ended work:

1. error idiom (exception / error union / multiple return)
2. lifetime idiom (`IDisposable` / `defer` / `__gc` / `__exit__`)
3. sequence type (`Span` / slice / table / buffer)
4. naming convention
5. callback mechanism
6. nullability representation
7. doc-comment format

Seven decisions plus a runtime shim. That is a checklist, so it is possible to know when a backend is finished.

**Why a shared middle is justified here when the INR was not.** `ScriptingArchitectureV2.md` §9.2 rejected an intermediate representation because it sat between one producer and **one** consumer — the C ABI was already the narrow waist, and the centralized work was ~150 lines of layout arithmetic. This sits between one producer and **N** consumers, and the shared work is real classification. Without it every backend re-derives "is this slot fallible?" from raw C types. The cost of that is not duplicated effort but **divergence**: if the C# backend treats `bool` + `ke_error**` as fallible and the Lua backend forgets, the languages disagree on semantics — the exact failure this project exists to prevent.

**Evidence that the seam is real**: the §5.5 prototype tangles both halves in one function — six classification decisions interleaved with five rendering decisions. That is precisely why it only serves C#.

### 6.3 Static and dynamic backends differ only in when they run

- **Static** (C#, Zig, Rust): the backend runs at build time and emits source.
- **Dynamic** (Python, Lua): the backend may emit nothing ahead of time, loading `ke_api.json` at import and constructing the surface through metaprogramming.

This is a scheduling difference, not a cost difference. A dynamic language still needs every one of §6.2's seven decisions — idiomatic Lua is far from C. An earlier draft claimed dynamic languages would be *cheaper* than C# and therefore under-test Track 3; under §0 that is withdrawn. **Every language exercises the full backend surface.**

### 6.4 ClangSharp's future

ClangSharp is retained for the raw P/Invoke layer while `kabic` is built on top of it. Once `CSharpBackend` can emit both layers, ClangSharp is removed — two parsers claiming to be the source of truth is exactly the drift this architecture exists to prevent. **Named as planned debt**, with the removal gated on `kabic` reaching parity, not on a date.

---

## 7. Track 4 — Node ergonomics (`ke_node_host`)

Separate, smaller, and lowest priority of the four: a native middle-end that collapses node-registration mechanics ("a struct's fields become a component, a lifecycle method becomes a system with an access list") so no language reimplements them. Design and rationale — including why its input is a **transactional builder API** and not a serialized IR — are in [`ScriptingArchitectureV2.md`](ScriptingArchitectureV2.md) §4/§5/§9.2, which remain valid.

Scope check: it removes ~600 LoC of the C# baseline. Real, but it is the smallest of the four tracks and it does not change the answer to "can any language use this engine". **It should not be started before Tracks 1 and 2 have a per-domain rhythm going**, because it registers into an ABI those tracks are still reshaping.

### 7.1 The growth problem node ergonomics create

Tracks 1–3 give a domain author this deal: write a C header, run `kabic`, every target language is supported. Node ergonomics break that deal if the node layer is per-language handwritten code.

Every domain eventually wants ergonomic nodes (`PointLight`, `CollisionShape2D`, `AudioPlayer`, …). If those live in a per-language toolkit, then a domain is not done when its header is done — it is done when someone has written its node classes in C#, *and* Lua, *and* Zig. The floor stops being `O(languages)` and becomes `O(languages × domains)`, and a community-authored domain is no longer "run `kabic` and ship".

That is the problem this track has to solve, and it is a stronger requirement than "remove ~600 LoC".

### 7.2 Finding: a node is a typed facade over a component

Measured against the current toolkit:

| Node | LoC | What it contains |
|---|---|---|
| `Sprite2D` | 12 | component fields |
| `AmbientLight` | 20 | component fields |
| `PointLight` | 25 | 3 fields; setter writes the component. No logic. |
| `MeshRenderer` | 26 | 2 handles; writes 2 components on bind |
| `DirectionalLight` / `SpotLight` | 27 / 31 | component fields |
| `AudioPlayer` | 48 | reads two scene properties, calls `load_sound`, exposes `Play()` |
| `CollisionShape2D` | 67 | ancestor search + `add_*_fixture` |

The base `Node` (151 LoC) is mostly component access (`LocalTransform`), lifecycle declarations, and a `Parent`/`_children` pair that **duplicates hierarchy the native `ke_scene_tree` already owns** — divergent state, not just redundancy, and the same class of leak the Track 1 rubric exists to catch.

So the dominant case is not code. It is a component schema plus a name.

### 7.3 Thesis: a node type is data, therefore `kabic` can emit it

If a node type is describable — name, base, backing component(s), property schema, defaults — then `kabic` generates the ergonomic type per language exactly as it already generates provider wrappers. The domain author writes no per-language code, and the floor returns to `O(languages)`.

The corollary is structural: **there is no `toolkit.<domain>`. A domain declares its own node types in its own header**, and `kabic` emits them into whatever that language calls that domain's module.

### 7.4 Mechanism: a tag on the component struct

The declaration reuses the tag vocabulary (§5.2) rather than introducing a second description mechanism:

```c
/**
 * [node:PointLight,base:Node3D] Emits light in all directions from this entity.
 */
typedef struct ke_point_light_component {
    float color[3];   ///< [default:1,1,1] Linear RGB.
    float intensity;  ///< [default:1]
    float radius;     ///< [default:10]
} ke_point_light_component;
```

`kabic` already extracts struct name, doc, field names, field types, and field docs. `[node:]` and `[default:]` add no new extraction concept — they ride the machinery `[utf8]`/`[out]`/`[try]` already proved. From this single declaration each backend emits its own idiom (a C# class with properties, a Lua metatable, a Zig struct with accessors), and `[default:]` supplies both the construction defaults and the scene-file property defaults.

### 7.5 What still will not generate

Additions to the §9 floor — each is **fixed per language and does not grow with the engine**:

- The object-model adapter inside `kabic`'s own backend that turns "class with a virtual method" into "entity + registered callback" for that language (§7.11) — not a per-language `Node` class, see the correction below.
- The DI / composition idiom.
- Game code (`Paddle`, `Ball`, …) — target-language by design, per §0.

A node behaviour that is genuinely imperative is not floor: it is misplaced. It belongs natively in the domain that owns it, as a system.

### 7.6 Open design questions

Unresolved, and each can invalidate part of §7.4:

1. **Imperative node behaviour — design closed by §7.14.2/§7.13's correction, implementation still open.** `render.mesh.resolve` (§7.13's correction) proved the pattern on `MeshRenderer`'s scene-apply logic; `CollisionShape2D` (physics: ancestor search + fixture attach) and `AudioPlayer` (audio: scene-property load + `Play()`) are still hand-written, still imperative, as of the 2026-08-05 dispersal (§8.4) — the same conversion, not yet done for either.
2. **Node methods — design closed, see §7.14.2.** Not a missing vtable-binding rule; inside a wave-parallel ECS a system body cannot call arbitrary domain code regardless of any declared rule. `Play()` is a command component (`play_requested`) a domain system consumes, the identical shape as §7.13's mesh resolution.
3. **Behaviour detection without reflection — design closed, see §7.14.4.** `Node.CompleteBind` (now in `KernelEngine.Framework/Scene/Node.cs`) still uses `GetType().GetMethod(nameof(OnUpdate), ...)` reflection, unchanged. `ke_node_host` (§7.14.4) replaces the discovery with a lookup against its own registration table — implementation not started.
4. **Base hierarchy prerequisite — partially resolved, differently than planned.** `Node2D` shipped 2026-08-05, but as a C# facade over the *same* `ke_transform_component`/`Node3D` every 3D node uses (`Position`/`Scale` as `Vector2`, `Rotation` as one angle, `Depth` for Z) — not the locked `FrameworkArchitectureV2.md` §7 design (a distinct `ke_transform2d_component`, a parent-chain restricted to Node2D-under-Node2D). The facade was the right call for the immediate need (Pong-style 2D games mixing freely with 3D nodes) and required zero native change, but it does not close this prerequisite for `Canvas`/`Control`, which still don't exist. `base:Node3D` node types (the 5 in §7.13) sidestep this question entirely — they don't need Node2D at all.

### 7.7 Alternatives rejected

- **No node types; a generic typed view** (`world.Get<PointLight>(e).Intensity = 5`). Removes the generated-type surface entirely, but discards the construction and subclassing ergonomics that are the reason this track exists.
- **A separate node manifest (TOML/JSON) instead of header tags.** A richer schema without C-comment constraints, but it establishes a second source of truth to keep synchronised with the headers — the exact failure mode §5.3 exists to prevent.

### 7.8 Validation plan

Same shape as Stage 1 (§8.3): prove on one domain before generalising. `PointLight` is the pilot — the pure case (one component, three scalar fields, no logic). The gate is whether the generated C# type is equivalent to the hand-written one. If it is not, the thesis fails cheaply and before any domain header has been annotated.

### 7.9 Pilot result — surface passes, component identity does not

Run on `ke_point_light_component` tagged `[node:PointLight,base:Node]`.

**Passed — the generated surface is a drop-in.** `kabic` emits `Vector3 Color` / `float Intensity` / `float Radius` with the documented defaults, and the four examples that construct point lights (`07_point_lights`, `09_many_lights`, `10_hdr_bloom`, `13_full_scene`) compile unchanged against it. The property surface, the defaults, and the write-through-on-set behaviour are all derivable from the header alone, as §7.3 claimed.

**Failed — the component identity is not.** At runtime: `Component type 'ke_point_light_component' is not registered with the framework.` `ComponentRegistry` maps a *managed* struct type to a cid (`Register<PointLightComponent>(ecs, "point_light")`); a generated node holds the *header* struct, which no registration mentions. The generated node writes a component the framework cannot name.

This is the concrete form of the duplication §7.6 predicted, now located precisely: **the same component is declared twice — once in the header, once as a hand-written C# mirror — and the managed one is what the registry keys on.** Until a component's identity comes from its header declaration, a generated node cannot address it.

**Correction to an earlier reading of this duplication.** The three declarations of `point_light` (header, C# `PointLightComponent`, a hand-copied Zig struct) were *layout-identical*; the render path worked because they agreed, not because anything linked them. A comment in the cluster pass asserted the header "orders them differently" — it did not. The hazard was latent, not active.

What the pilot changed as a consequence: the Zig cull pass now reads `c.ke_point_light_component` from the header instead of its own copy, and the header spells the colour as `float color[3]` rather than three scalars — the same twelve bytes, now expressing the grouping a node surface needs. Four producers had to move together (header, cull pass, the scene-loader apply path, and a GTest asserting the old field names), which is itself the measure of how unlinked the declarations were.

**The remaining step before generalising**: component identity must derive from the header — either the managed mirror is generated from it, or the registry registers the header type directly. Node-type generation is blocked on that, not on anything in §7.4.

### 7.10 Component identity is a name, not a type — and that is what makes user-defined nodes work

Both options §7.9 closes on assume a header exists. For a game-authored node type there is none, and there never will be: a game's `Paddle` is not exported to any other language, so nothing would generate a header for it. Posing the choice as "generate the managed mirror" versus "register the native type" was therefore a false dichotomy — neither serves the case that matters most for the toolkit growth curve.

What both paths do share is the ECS contract itself: `component_register(name, size) -> cid`. **Name plus size is the identity; a managed `Type` or a C struct is only ever a local handle onto it.** `ComponentRegistry.CidOf<T>()` is a convenience over that truth, and it is exactly the convenience that failed the pilot.

So a generated node resolves its cid by name:

| | engine node type (`PointLight`) | game node type (`Paddle`) |
|---|---|---|
| source of truth | the domain's header | the class, in the game's own language |
| who generates | `kabic`, into every language | that language's own codegen |
| exists in | every target language | only the game's language |
| result | a **named component** in the ECS | a **named component** in the ECS |

The runtime cannot tell which path produced a component, and does not need to. The name for an engine type is derived from its component struct (`ke_point_light_component` -> `point_light`, via `Convention.ComponentSuffix`); the name for a game type comes from whatever its language's codegen assigns.

This is what keeps the per-language floor flat. Engine node types grow with the engine but cost nothing per language, because they are generated — a community domain ships a header with `[node:]` tags, runs `kabic`, and every language has the type. Game node types never enter any toolkit at all. What each language implements by hand stays fixed: the codegen that turns a class's fields into a named component, and the object-model adapter in §7.11.

**Pilot re-run, passing.** With name-based resolution, `PointLight.g.cs` replaces the hand-written class outright: the four examples that construct point lights compile and run against it, 122 managed tests and 236 native tests pass, and no other domain's generated output changes except for comment removal. `NodeWorld` gained `SetByCid` and `CidOfName` — the two operations a name-identified component needs, both of which a game-authored node will use unchanged.

**Open hazard, found 2026-08-05, not yet fixed — see §7.14's own §7.14.7.** "Name plus size is the identity" is only true if `component_register` actually *checks* the size on a name collision. It does not: `ecs_flecs.zig`'s `componentRegister` looks the name up and, if found, returns the existing cid unconditionally — no size comparison. Two unrelated game-authored `Paddle` types (different projects, different field layouts, generator-assigned the same name) silently alias the same cid; the second registrant's writes land at the first's (smaller or larger) stride. This is the identical bug class already paid for once — `FrameworkModule.cs`'s comment on `ComponentRegistry` registration order describes the same corruption from `transform` registered at two different sizes — now generalized from "wrong init order within one process" to "two strangers' generated names collide," which becomes a real scenario the moment user-defined node types ship in a product (§7.14).

### 7.11 Correction — `Node` is not hand-written floor either, it is native state duplicated in C#

§7.5 previously counted `Node` (~150–250 LoC) as fixed per-language floor, on the assumption that entity lifetime, hierarchy, and lookup have no native form and must be reimplemented per language. That assumption is false, checked against what already ships:

- `ke_scene_tree` (`scene_tree.h`) already exports `create_node`, `destroy_node`, `find_node`, `root`, and `propagate_transforms` as vtable slots.
- Entity name is `ke_name_component`; parent/children is `ke_hierarchy_component`. Both are native components, not C# state.

Read against that, `NodeWorld`'s `_byName`, `_allNodes`, `_byEntity` are a fifth leak of the same shape as the three closed this session: a managed mirror of state the native side already owns, kept in sync by hand instead of queried. `Node.Parent`/`_children` is the same leak inside the node object itself.

What is genuinely irreducible is narrower than "the whole base class": dispatching a call from native code into a script object's overridden method. That needs a small native primitive, `ke_node_host`, mirroring the existing callback-vtable pattern already proven for e.g. `ke_logger_sink`:

```c
typedef struct ke_node_host {
    void (*register_behavior)(struct ke_node_host *self, ke_entity entity,
                               void (*on_update)(void *user_data, float dt),
                               void *user_data);
    void (*unregister_behavior)(struct ke_node_host *self, ke_entity entity);
} ke_node_host;
```

With `ke_scene_tree` for lifetime/hierarchy/lookup and `ke_node_host` for behavior dispatch, nothing is left that needs per-language hand state. `Node` becomes a **generated** wrapper — same mechanism as `[node:]` on a component, but its "component" is the pair `(ke_name_component, ke_hierarchy_component)` plus a callback registration, not a single data struct. `Node3D`/`Node2D`/`Control`/`Canvas` then generate as `base:Node` types the same way `PointLight` generates as `base:Node3D` — no hand-written class at any level of the chain.

The only thing that stays genuinely per-language, because it cannot be anything else, is the adapter inside `kabic`'s own backend translating "this language's virtual-dispatch idiom" into a call to `register_behavior` — a C# `delegate`, a Lua closure over a table, a Zig function pointer stored on a struct. That code lives once, in the backend, not once per domain and not once per game.

### 7.12 C#'s node properties move to a shared Roslyn generator, not per-field kabic output

`RenderNodeType`'s first working version (§7.9/§7.10) emits a full get/set body per field directly into the `.g.cs` — each property reads the live component via `Current()`/`TryGetByCid` and writes it back via `SetByCid`, correcting the caching bug §7.9 originally shipped with. That body is identical in shape for every field of every node type; kabic was hand-rolling, per domain, exactly the boilerplate a single generator should own once.

C# 13 (stable on this project's `net10.0` target, verified in-session) allows a **partial property**: one partial declaration gives the signature, another supplies the accessor bodies. This closes the gap the C# side of `FrameworkArchitectureV2.md` §5.5 was reaching for — not by rewriting fields (Roslyn generators are additive-only; a field's backing storage cannot be intercepted, only a `partial` property's body can), but by generating properties. `kabic`'s C# backend now only needs to emit:

```csharp
public partial class PointLight : Node3D
{
    public partial Vector3 Color { get; set; }
    public partial float   Intensity { get; set; }
    public partial float   Radius { get; set; }
}
```

**Implemented** as `KernelEngine.SourceGenerators` (`src/csharp/generators/`), a single Roslyn `IIncrementalGenerator` finding every `partial` property on any `Node`-derived class and emitting the second partial declaration with the ECS-backed body. It is the same generator, unmodified, whether the declaring partial class came from `kabic` (an engine node type, header-derived) or was hand-written by a game author (§7.10's game-node-type case, and `FrameworkArchitectureV2.md` §5.5's original goal of game code not needing to know it is in an ECS).

Building it surfaced a case §7.4's tag vocabulary doesn't cover from the property signature alone: `PointLight.Color` is `Vector3` in C# but `float color[3]` in the header — same twelve bytes, different shape, and the field is even named in a different casing. A generic "infer everything from the property" rule cannot bridge that; it needs two small markers, both plain C# attributes living in `KernelEngine.Toolkit`, not new tag-vocabulary syntax:

- `[GeneratedNodeComponent(typeof(ke_point_light_component), "point_light")]` on the class — present only on `kabic` output. Its absence is exactly what tells the generator "no header, synthesize a backing struct named `<Class>_Data` and register it fresh via `NodeWorld.RegisterComponent`" instead of resolving an existing name via `NodeWorld.CidOfName`.
- `[NativeField("color")]` on a property — names the backing field when it is not simply the property name, and (paired with the property's own `Vector2/3/4` type) is what tells the generator to expand a lane-grouped native field into per-component array writes, the same transform `VectorArity`/`FieldInit` did inline in the pre-generator `RenderNodeType`.

So `kabic`'s job is exactly: emit the class, the two attributes, the `partial` property signatures, and a constructor seeding `[default:]` values into the private field the generator itself declares (`_generatedState` — a private member is visible across every partial declaration of the same class, which is what lets `kabic`'s constructor and the generator's accessors share it without either seeing the other's file). Never an accessor body.

This also answers §7.6 open question 3 (behaviour detection without reflection) for the property-backing case: everything resolves at compile time from the partial declarations and attributes Roslyn already sees, no runtime `GetMethod` lookup.

**Checked against every hand-written node in the toolkit, not just `PointLight`: `OnBind` never does anything but write the class's own component(s).** `AudioPlayer`'s scene-property read and `CollisionShape2D`'s ancestor search — both imperative, both real — live in `OnReady`, a different hook the generator does not touch; their `OnBind` is empty. So the generator owning `OnBind` outright, as it does today, is not the constraint it first looked like — it costs nothing on any node examined. The one real holdout was `MeshRenderer`, which wrote *two* components from the same two fields (`MeshRendererComponent` for the removed legacy bgfx path, `MeshComponent` for render-v2) — the generator resolves exactly one backing component per class. That duplication was dead-path debt, not a case the generator needed a feature for: `MeshRendererComponent` had zero native readers left (bgfx is gone), so it and its registration were deleted outright rather than accommodated; `MeshRenderer` now writes only `MeshComponent`.

Verified: `PointLight` regenerated through this path (attribute-driven, zero hand-written accessor) compiles unchanged into the four examples that construct point lights, and the full managed suite (94/95, the one failure pre-existing and unrelated — a native `configuration_create` environment issue, confirmed via `git stash`) passes. `AmbientLight`, `DirectionalLight`, `SpotLight`, and `Skybox` converted the same way immediately after — all four backing structs (`Render.Abstractions/Components.cs`) already mirror their property names and types 1:1, so no `[NativeField]` was needed on any of them, only `[GeneratedNodeComponent]` plus the `partial` signatures. Same result: unchanged callers, same test count.

**`Camera` surfaced a third field-mapping gap the marker mechanism does not cover yet: a type conversion, not just a name or a vector-arity difference.** `CameraComponent.Orthographic` is `byte` (the ABI has no `bool`); the property is `bool`. `[NativeField]` renames a field; it does not know how to convert one. Left hand-written rather than forced through the mechanism as-is — `Camera`'s own properties don't even write-through after bind today (`{ get; set; }` plain auto-properties, written once at `OnBind` and never again), a separate, older gap from the caching bug §7.9 fixed everywhere else. Both are the same class of problem the generator will need a real answer for before `Camera` converts: a declarative type-coercion rule (bool↔byte, and whatever the next domain's header throws at it) rather than one-off cases.

**Fields are out of scope for this mechanism, permanently — not a scheduling gap, a Roslyn constraint.** A generator cannot intercept a plain field's backing storage or a plain auto-property's existing accessor bodies; only a `partial` property's body is open for a second declaration to fill in. `public float Speed = 5f;` silently backed by ECS, with no `partial` anywhere, needs IL post-processing after compilation (Fody-style) — the same technique Unity DOTS uses for its own component authoring. That is a distinct, heavier mechanism (a build-time IL rewrite step, not a source generator) and is not started; it is the known path if `partial` on properties ever proves to be real adoption friction for game authors, not a hypothetical fallback invented to sound complete.

Consequences that ride for free once a property is generator-backed: uniform serialization (save/load = serialize the world), hot reload (state in ECS, not C# heap), networking (replicate the backing component), determinism (no hidden heap state), editor inspection (reads the backing component directly).

### 7.13 The pilot generalized — 5 of 7 render node types now generate (2026-08-05)

§7.9's pilot resolved `PointLight`; this session ran the same mechanism across the rest of `components.h`. `[node:]`/`[default:]` tags added to `ke_camera_component`, `ke_directional_light_component`, `ke_spot_light_component`, `ke_ambient_light_component`; `kabic` now emits `Camera.g.cs`, `DirectionalLight.g.cs`, `SpotLight.g.cs`, `AmbientLight.g.cs` alongside `PointLight.g.cs` — the 4 hand-written classes they replaced are deleted.

**Two tag-vocabulary gaps closed to make this generalize:**

- **`[bool]`.** `ke_camera_component.orthographic` is `uint8_t` (no `bool` in C) but the idiomatic C# property is `bool`. `CSharpBackend.NodePropertyType` now checks `f.Has("bool")` and emits `bool` instead of the raw byte type; `NodePropertyGenerator`'s existing `CoercionFor(bool, byte)` (already written for this exact case, previously unreachable) bridges the accessor body. No change needed on the generator side — the gap was entirely in what `kabic` chose to *render* as the property type, not in the generator's ability to back it.
- **`[name:X]`.** A field's Pascal-cased name (`near_plane` → `NearPlane`) doesn't always match the idiomatic property name callers already use (`Near`). Rather than rename 14 examples, `kabic`'s field loop now checks `f.TagValue("name")` before falling back to `Idioms.Pascal(f.Name)` — one line in `CSharpBackend.RenderNodeType`, matching the existing `[default:]` tag's shape. Used on `ke_camera_component.near_plane`/`far_plane` (→ `Near`/`Far`) and `ke_spot_light_component.inner_angle`/`outer_angle` (→ `InnerAngleDeg`/`OuterAngleDeg`).

**A third, larger gap surfaced and was *not* closed — two node types stay hand-written on purpose:**

- **`MeshRenderer`** (`ke_mesh_component`) has a `char primitive[32]` field. `NodePropertyType`/`FieldInit` only understand scalars, `[bool]`, and `float[N]` (→ `VectorN`); a fixed char buffer has no mapping and — separately — that field is written by the scene-loader's property-apply path, never by the node itself, so generating a property for it would be both wrong and unwanted.
- **`Skybox`** (`ke_skybox_component`) has `ke_texture_handle cubemap`. `CsType` would render the raw ClangSharp struct name (`ke_texture_handle`), not the idiomatic wrapper (`TextureHandle`) every hand-written node/example actually uses — the same class of gap `[bool]` just closed, but for handle types instead of booleans, and not designed yet.

Both gaps are noted in `components.h` itself (next to the un-tagged structs) so a future pass doesn't have to rediscover them by reading the generator.

**Correction, 2026-08-05, same day: `MeshRenderer`'s gap was never a `kabic` problem.** The reasoning above ("the field is written by the scene-loader's property-apply path, never by the node itself") undersold what was actually going on — `MeshRenderer.cs` was, and remains, a pure two-field facade (`MeshHandle`/`MaterialHandle`, written straight through); it never touched `primitive` at all. The real hardcoded logic (primitive-name → mesh handle, color/roughness/alpha → material handle) lived in `WebgpuRenderModule.OnLoad`'s C# apply callback — imperative resolution logic sitting *beside* the node, not inside it, misdiagnosed here as a node-generation gap because the symptom (a field kabic can't map) and the disease (logic in the wrong place) happened to point at the same struct. Moving that resolution into `render.mesh.resolve` (a native `KE_PHASE_UPDATE` system, §7.14's thesis applied concretely) fixed the actual problem; `MeshRenderer` itself needed zero changes, because it was never broken. The `char primitive[32]` mapping gap this section describes is real and still open, but it now blocks only one thing honestly: kabic generating `MeshRenderer.g.cs` outright to replace 6 hand-written lines, not "MeshRenderer working."

**Directional/spot/ambient light's underlying ABI changed as a side effect, audited across every producer.** Making `Color`/`Direction`/`Ambient` into `Vector3` requires the native field to be a contiguous `float[3]`, not three named scalars (`r, g, b` / `dir_x, dir_y, dir_z` / `ambient_r, ambient_g, ambient_b`) — same layout, different field spelling. Every native reader was updated in the same change: `shadow_module.zig`, `forward_module.zig`, `deferred_lighting_module.zig` (direct field reads), `components_apply.zig`'s scene-loader appliers (kept the old scalar TOML keys — `dir_x`, `r`, `g`, `b` — as accepted aliases writing into the new array slots, so no `.scene` file needed to change), the frozen `test_scene_loader.cpp` GTest, and one C example (`examples/c/14_forward_mesh/main.c`).

**Where the generated node types physically live changed too — see §8.4.** `Camera.g.cs`/etc. are no longer under a `toolkit` project; the manifest entry that drives their generation (`scripts/api_domains.json`, entry `render_components`) is explicit that it is *not* a separate native plugin — `components.h` is part of `src/c/render`, same as `world`/`scene_tree`/`scene_loader`/`input_actions` are four manifest entries under one native `framework` plugin, not four plugins.

### 7.14 The node facade architecture — designed 2026-08-05, not started

Everything above (§7.1–§7.13) treats one node at a time: can `kabic` generate *this* node's properties. That question kept surfacing the same deeper one — `MeshRenderer` "looked" hard to generate for the same reason `Skybox` didn't (§7.13's correction) and the same reason the original `LabelUiSystem` sat inside the `render.ui` draw pass instead of its own system (§8.4's UI-ownership work): **logic was hardcoded beside or inside a node, instead of living in a system.** A node with logic can't be generated, because generating it means generating the logic too, and logic is exactly the part that has no mechanical shape. A node that is pure data can always be generated, because "pure data" is by definition just a schema. So the node-generation question was never really about `kabic` — it is about whether the *architecture* keeps nodes as data. This section designs that architecture, prompted by asking what a Godot-rich node system (signals, groups, coexisting builtin and user node types) would need on top of what §7.1–§7.13 already built, and finding that the current `Node`/`NodeWorld` (even after §8.4's toolkit split) still carry state that should not exist.

#### 7.14.1 The principle: a node is a projection, not an object

`Node` today is a hybrid: some of its state is genuinely its own (nothing — checked, see below), and some is a **managed copy of native truth**, kept in sync by hand:

| Field | Duplicates | Status |
|---|---|---|
| `Node.Name` | `ke_name_component` | **emptied 2026-08-05** — `Name` reads `NodeWorld.GetName(Entity)` live, no cached field |
| `Node.Parent` / `_children` | `ke_hierarchy_component` | **emptied 2026-08-05** — `Parent`/`Children` walk `ke_hierarchy_component` live via `NodeWorld.GetParent`/`GetChildren`; `AttachChild`/`DetachChild` deleted outright, nothing left to sync |
| `Node.HasBehavior` | computed via reflection over `OnUpdate` | not started — waits on `ke_node_host` (item 3) |
| `NodeWorld._byName` | `ke_scene_tree.find_node` | **emptied 2026-08-05** — `Find` calls `SceneTree.FindNode` and resolves the returned entity through `_byEntity` |
| `NodeWorld._allNodes` | a query over every bound node | not started — no native "is a managed node" marker exists yet to query on, and `TriggerReady`'s reverse-DFS-order contract needs a real ordered list; `Dictionary.Values` iteration order is an implementation detail, not something to build a documented contract on |
| `NodeWorld._behaviors` | what `ke_node_host` (§7.14.4) should own | not started — same as `HasBehavior` |

Every one of these is the same shape of leak §6.5/world.zig/§8.4's toolkit-dispersal work already found and fixed at the native and C# layers, just one level up: a managed mirror of state the ECS already owns. As long as any of it exists, a node type is not just a schema — it is a schema *plus* synchronization code, and synchronization code cannot be generated from a header. Emptying it is the precondition for everything else in this section, including for §7.6's still-open questions 1–3.

**Three of six rows done.** `Name`/`Parent`/`Children`/`Find` no longer duplicate anything — every read goes straight to the ECS, so a native rename, reparent, or destroy is visible on the next access with no sync call anywhere. Verified: full `dotnet build` (no warnings introduced), the native `SceneTreeTest` suite (unaffected — this was a pure C# read-through change, no ABI touched), and a 6-second live run of `examples/csharp/games/pong` (which builds a real parent/child hierarchy and calls `Find<T>()` from game code) with no exceptions. `_allNodes`/`_behaviors` stay exactly because §7.14.9 already flagged them as blocked on `ke_node_host` — this is not a new finding, just confirmation the dependency is real once the easy two-thirds were actually attempted.

#### 7.14.2 Decomposition — what a rich node system needs, and what actually requires new native machinery

| Capability | Where it lives | New native machinery? |
|---|---|---|
| Identity | `ke_entity` | no |
| Name | `ke_name_component` | no |
| Hierarchy | `ke_hierarchy_component` + `ke_scene_tree` | no |
| Typed data | a domain's own component(s) | no |
| **Groups** | a zero-size tag component per group | **no — already works, unused** |
| **Node methods** (`AudioPlayer.Play()`) | a command component the owning domain's system consumes | **no — same shape as `render.mesh.resolve`** |
| Imperative behavior | domain systems (native, KE_PHASE_UPDATE/RENDER) | no |
| **Signals** | a native bus; connections are components (durable), emission is transient | **yes** |
| **Callback dispatch** (`OnUpdate`, etc.) | `ke_node_host` | **yes** |

Two capabilities collapse into the existing component/query machinery with no new design at all:

- **Groups are tags.** `AddToGroup("enemies")` is `component_register("group.enemies", 0)` + `attach`; `GetNodesInGroup` is a query. `component_register` with `element_size = 0` already exists and is already used (`"backbuffer"`, `"render.frame"`) — groups are not a future feature, they are an unused application of a mechanism this engine already has.
- **Node methods are commands, not vtable slots.** §7.6 open question 2 ("Node methods — no declarable rule exists yet binding a node to one of its domain's vtable slots") was posed the wrong way: inside a wave-parallel ECS, a system body cannot call arbitrary domain code directly regardless of any declared rule — the wave-parallelism itself forbids it, independent of code generation. `AudioPlayer.Play()` is not a method to generate a binding for; it is `attach(entity, play_requested_tag)`, consumed by an audio-domain system the same way `render.mesh.resolve` (§7.13's correction) consumes `ke_mesh_component`. This closes §7.6 question 2 as a design question — what remains is applying it to `AudioPlayer`/`CollisionShape2D`, an implementation task, not an open question.

#### 7.14.3 Signals — connections are durable, emission is not

Godot's signal system splits into two lifetimes that must not be conflated:

- **Emission** is a single frame's event — transient, drained at a phase boundary (a ring buffer, same shape as any other per-frame producer/consumer split in this engine).
- **Connection** (node A's signal wired to node B's handler) is **durable** — it must survive scene serialization (Godot saves connections in the `.tscn`) and, in this engine's actual current use case, must be visible cross-language: if a Lua-authored node connects to a signal a C# builtin node exposes, the connection cannot live only in Lua's runtime, because nothing about a *component* is language-scoped (§7.14.5) and a signal connection is exactly that kind of fact. **A connection is a component** (`ke_signal_connection_component` — source entity/signal id, target entity, handler command shape), not a callback closure kept in one language's heap. This is the one piece of §7.14.2 that is not already free: a signal bus (registration + emission + drain) is new native surface, `src/c/framework/` or a sibling to `ke_scene_loader`.

#### 7.14.4 `ke_node_host` — the callback trampoline, and what it fixes

The dispatch primitive `ScriptingArchitectureV2.md` §4/§5 already specified and §7.11 already named as the honest floor. Two jobs: register a behavior callback for an entity, and call it. Landing it fixes §7.6 question 3 outright — `Node.CompleteBind`'s `GetType().GetMethod(nameof(OnUpdate), ...)` reflection (still present, unchanged, as of this section) exists only because nothing native currently tracks "does this entity have behavior registered"; once `ke_node_host` owns that table, discovery is a lookup, not a reflection probe, and the result is no longer C#-specific (it stops being a `Node.CompleteBind` mechanism and becomes a runtime one, satisfying the script-safety model's reflection ban for the same reason `ke_render_ui`'s font table replaced C#'s per-`Font` `Dictionary` in §8.4's label work).

**Done (2026-08-05), native + C# SDK layers — the Roslyn frontend and scene_loader wiring (§8) are still open.** Implemented per `ScriptingArchitectureV2.md` §4/§5 exactly as specified there:

- **Native** (`src/zig/framework/include/kernel_engine/framework/node_host.h` + `node_host_create.h` + `src/zig/framework/src/node_host.zig`): the full transactional builder (`begin_type`/`commit`/`spawn`/`attach`/`describe`), with `commit()` verifying field types (rejecting `STRING`/`TABLE` as non-blittable), computing field layout (natural per-type size/alignment, no reliance on `ke_variant`'s own wasteful union layout), resolving every `access()` component name (self-reference to the type's own just-registered component, or an existing `component_lookup`), capping per-hook access count at `KE_QUERY_MAX_TERMS`, and registering nothing at all if any check fails — then, only on success, registers the component (exercising the §7.14.5 size-validation fix live), builds one `ke_query_decl` per hook from its declared accesses, and registers one `ke_runtime` system per hook whose `execute` callback (`hookExecute`) walks `ke_system_ctx_view` and dispatches once per resolved segment (not per entity, per `ScriptingArchitectureV2.md` §5's load-bearing performance decision). v0 hook table is the doc's own honestly-scoped floor: only `KE_NODE_HOOK_UPDATE → KE_PHASE_UPDATE`; `OnBind`/`OnReady`/`OnUnbind` are additive, not mapped yet. Six `zig build test` cases (a fake in-process `ke_ecs`/`ke_runtime` vtable, not a real flecs/enkiTS backend — keeps this plugin's own tests as storage-agnostic as the plugin itself, and was enough to cover every `commit()` verification branch).
- **Build wiring**: `node_host.zig` is the first file in this plugin to call a free exported function from another plugin's `.so` directly (`ke_system_ctx_view`, from `ke_runtime`) rather than only through a caller-supplied vtable pointer — `src/zig/framework/build.zig` gained a `-Dke-lib-dir` option and `linkSystemLibrary("ke_runtime")` (root `build.zig`'s `framework` plugin registration now depends on `runtime.step`), mirroring the precedent already established by `render/service`'s own build.zig for the same reason.
- **C# SDK, mostly generated, not hand-written**: added `node_host` as a `scripts/api_domains.json` domain (same "not a separate native plugin" shape as `world`/`scene_tree`/`scene_loader`). `kabic` generates `NodeHost.g.cs` (`BeginType`/`Commit`/`Spawn`/`Attach`/`Describe`, `out_error`→`KernelError` translation included, zero hand-written code) and `NodeTypeBuilder.g.cs` (`Field`/`Access`) with no changes to the generator needed. The one method kabic cannot generate — `NodeTypeBuilder.Hook()`, because `ke_node_hook_fn` is a raw C function-pointer typedef with no shape a generic backend can infer — is tagged `[idiom]` in `node_host.h` (the same escape hatch `ke_scene_tree.root` already uses) and hand-written in `NodeTypeBuilder.Idiom.cs`: a `GCHandle`-pinned managed delegate dispatched through a static `[UnmanagedCallersOnly]` trampoline, exactly the "GCHandle-pinned dispatcher lifetime management" `ScriptingArchitectureV2.md` §6 always scoped as SDK glue, not codegen. Verified end-to-end in `tests/csharp/KernelEngine.Runtime.Tests/NodeHostTests.cs` against a **real** flecs `ke_ecs` + enkiTS `ke_runtime` (not a fake, unlike the Zig unit tests — this is the one place a real `Tick()` actually has to fire the trampoline to prove the design closes the loop): register a type, spawn an entity, tick the runtime, and observe the managed callback receive that exact entity.
- **A real generator gap found and fixed along the way, not just a node_host special case.** The first regeneration attempt used the same shared `Generated/` directory `world`/`scene_tree`/`scene_loader`/`input_actions` already share, and clobbered `input_actions`'s `Enums.g.cs` — `generate_csharp.cs`'s `--enums-out` does `File.WriteAllText`, an overwrite, not a merge, and nothing before this had ever put two enum-bearing domains in the same directory. Fixed by giving `node_host` its own `abstractionsOutDir` subfolder (the same field `input`/`logger`/`physics` already use for exactly this separation) — a real, if narrow, gap in the shared-directory convention, not a one-off workaround.
- **Not started**: the Roslyn incremental generator (`ScriptingArchitectureV2.md` §6's "frontend" — `class Player : Node { float speed; void OnUpdate(...) }` → generated `BeginType`/`Field`/`Hook`/`Access`/`Commit` calls, zero hand-written registration at the call site) and the `ke_scene_loader` script-factory wiring (§8 — `attach()` as the implementation of `ke_script_factory_func`). Both are real, separately-scoped pieces of work; nothing here should be read as claiming they're done.

#### 7.14.5 The name-collision hazard `component_register` doesn't guard against

`§7.10`'s "name plus size is the identity" is only as strong as the registration function that enforces it. It doesn't: `ecs_flecs.zig`'s `componentRegister` does `ecs_lookup(world, name)`, and if that finds an existing entity, returns its cid **without comparing `size`**. Two independently-authored `Paddle` node types (different projects or plugins, generator-assigned the same name because nothing today qualifies it beyond a bare class name) silently alias the same cid; whichever registers second gets the first's cid at the first's stride, and every write past that boundary corrupts adjacent component storage. This is not hypothetical — it is the identical failure `FrameworkModule.cs`'s registration-order comment already documents having hit once (`transform` at 104 bytes vs. 40), generalized from "wrong init order in one process" to "two node authors who never met." It becomes a real, not theoretical, scenario the moment user-defined node types ship in a product with plugins or multiple contributors — which is exactly this section's premise. Two independent, cheap fixes, both blocking before user-defined nodes are a real feature:

1. **`component_register` must reject a size mismatch** instead of silently returning the existing cid — `KE_COMPONENT_INVALID` + `ke_error`, the `ke_result` doctrine already used everywhere else, in place of the corruption-on-write this currently degrades to. **Done (2026-08-05):** `ke_ecs.h`'s `component_register` gained an `out_error` parameter; `ecs_flecs.zig`'s `componentRegister` now compares the existing registration's size (via `ecs_get_type_info`) before reusing a cid, and fails the call instead of aliasing. `kabic`'s generated `EcsRegistry.ComponentRegister` idiom picked this up automatically (`out_error != null` → `throw KernelError.FromNative(...)`) — no hand-written C# needed, the generator already knew how to translate an `out_error` param into an exception. Covered by two new `zig build test` cases in `ecs_flecs.zig` (`componentRegister rejects re-registering a name with a different size`, `componentRegister is idempotent for a repeated identical size`).
2. **Generated component names must be collision-resistant** — qualified by the owning assembly/module (or an explicit namespace a build declares), not a bare class or namespace name, so two strangers' `Paddle` never collide by coincidence. Not started; (1) turns the collision from silent corruption into a loud, attributable error, which is the load-bearing half — (2) is what stops the error from happening at all.

#### 7.14.6 What survives in the managed layer, deliberately

Not everything in `NodeWorld` is a leak. `_byEntity` (the identity map: entity → the one live managed instance) stays — it is not a copy of native truth, it is the thing every object-oriented host language's own model requires: `Find("Player")` called twice must return the *same* instance (reference equality, subclass state, anything the game stored on it), and nothing native can hand that back — an entity id is not an object identity in C#'s sense. This is the "node access funnel" §9 already names as permanent floor, now scoped precisely: one map, keyed by entity, owned per language runtime, nothing else.

#### 7.14.7 `Find<T>()` across languages — resolved by publication, not by which language authored the node

First pass at this question conflated "which language created the node" with "which languages can consume it" — wrong axis, corrected in discussion. The real axis is **whether a node type's schema is published**, independent of source language:

| | schema published? | `Find<T>()` |
|---|---|---|
| Engine builtin node (`PointLight`) | yes, the domain's header | works everywhere — `kabic` generates `T` per language, as §7.1–§7.13 already do |
| Game node, exported | yes, the game publishes its own schema | identical machinery — no privileged path for "the engine's own" node types |
| Game node, internal (not exported) | no | only the authoring language has `T`; every other language sees the entity's raw component data, untyped — which is what *not* exporting means, not a limitation to route around |

Within one language, sharing a node type across two projects needs nothing new — it is that language's own module system (an assembly reference, an `import`, a `@import`), the same way any two C# projects already share a type today. Component **identity**, in the ECS, is always the registered name regardless of which axis is in play; that part of §7.10 was already correct and needs no revision.

The consequence that makes the whole design close: because every node is either **data** (a component, always projectable into any language that has the schema), a **command** (§7.14.2, likewise), or a **dispatched callback** (`ke_node_host`, §7.14.4, which does not care which language registered it), there is no remaining category of "thing a node does" that only one language's runtime can reach. The earlier draft of this design flagged a cross-language `Find<T>()` gap as an inherent limitation; it was not — it was two capabilities (dynamic-language export, size-checked registration) not yet built, not a ceiling on the design.

**One consequence for dynamic-language export specifically.** A Lua- or Python-authored node exporting its schema needs more than today's `component_register(name, size)` runtime call — that is enough for the ECS to store the data, but not enough for `kabic` to *generate* `T` in another language, which needs the field list, same as any `[node:]`-tagged C struct does. Exporting a dynamic-language node type is therefore a reverse-codegen path (source → `kabic`'s IR), not just a registration call; not designed yet.

#### 7.14.8 A concrete behavioral hazard, found auditing `scene_tree.zig` for this section

Emptying `Node._children` to read live from `ke_hierarchy_component` changes observable order, not just internal wiring. `scene_tree.zig`'s `populateNode` **prepends** each new child (`h.next_sibling = ph.first_child; ph.first_child = entity`) — a native child list iterates in reverse insertion order. `Node._children`, today, is a C# `List<Node>` built with `Add` — insertion order. Any game code iterating a node's children (UI layout, turn order, anything positional) observes different behavior the moment `_children` stops being its own list and starts reading the native list directly. This needs a conscious decision before §7.14.1 removes it — most likely reversing `scene_tree.zig`'s link direction to append (an O(1) prepend-to-tail-pointer change, not an O(n) walk), matching Godot's own stable indexed child order, rather than teaching every consumer to expect reverse order.

**Done (2026-08-05).** `ke_hierarchy_component` gained a `last_child` field (`components.h`); `populateNode` now appends (`ph.last_child`'s old occupant gets `next_sibling = entity`, or `first_child = entity` when the parent had none yet), and `destroySubtree`'s unlink path keeps `last_child` consistent when the removed node was the tail. Audited every producer: the C# `HierarchyComponent` mirror (`KernelEngine.Ecs.Abstractions`) gained the matching `LastChild` field in the same struct position; no other native or managed code reads `ke_hierarchy_component` directly. Covered by a new GTest, `SceneTreeTest.CreateNode_SiblingsLinkInInsertionOrder`, asserting the walk order and `last_child` explicitly. This was exercised as a live test of the same-day `component_register` size-validation fix (§7.14.5): the size change is exactly the kind of edit that fix now catches if any stale registration path forgets to update.

#### 7.14.9 Proposed order

Ranked by what unlocks the most next, per discussion:

1. ~~**`component_register` size-validation**~~ (§7.14.5) — **done 2026-08-05.**
2. **Empty `Node`/`NodeWorld`** (§7.14.1, §7.14.8) — the precondition for the rest; nothing else here is generatable while it duplicates native state. **Partially done 2026-08-05**: the child-order prerequisite (§7.14.8), and `Name`/`Parent`/`Children`/`Find`/`_byName` (§7.14.1) are emptied — all four now read live from `ke_name_component`/`ke_hierarchy_component`/`ke_scene_tree.find_node`. `_allNodes`/`_behaviors` remain, correctly blocked on item 3.
3. **`ke_node_host`** (§7.14.4) — **native + C# SDK layers done 2026-08-05**, closes §7.6 question 3 (the reflection dependency itself), verified end-to-end against a real flecs+enkiTS runtime. The Roslyn frontend generator and `ke_scene_loader` script-factory wiring (§8) remain — those are what would let a game author write `class Player : Node { ... }` and never call `BeginType`/`Commit` by hand.
4. **Groups** (§7.14.2) — cheap, and proves the "everything is a component" thesis end-to-end before the harder case.
5. **Signals** (§7.14.3) — the largest, and the one that most benefits from 2–4 already landing (connections are components; components are cheap once nodes are pure facades).

---

## 8. The plan — stages to zero hand-written wrappers

### 8.1 Terminal state

"Remove the hand-written C#" does not mean zero C# files. It means:

- **Zero hand-written per-domain wrappers.** No `Input.cs`, no `NativeInputActions.cs`, no `EcsRegistry.cs`. Every type mirror, every vtable method, every enum, every doc comment is generated from `ke_api.json`.
- **Zero engine capability above the ABI.** Nothing a Lua game would need lives only in C#.
- **What remains** is the §9 floor: ~300–400 lines of language-runtime plumbing, the DI/composition idiom, and the node access funnel. None of it grows when the engine gains a feature.

Measured target against the §1.1 baseline: **5 195 hand-written code lines → ≤ 500**, and **1 793 doc lines → 0** (they move into the headers and serve every language).

### 8.2 Stage 0 — `kabic` infrastructure (done)

| Step | Deliverable | Status |
|---|---|---|
| 0.1 | Tag vocabulary (§5.2) | Proven on `ke_input`/`ke_logger`: `[enum:T]`, `[out]`, `[out,array_of:count]`, `[borrowed]`, `[nullable]`, `[callback]` |
| 0.2 | `scripts/extract_api.cs` — `kabic`'s frontend: clang AST → `ke_api.json`, `@param` validated against the real signature | Done |
| 0.3 | `scripts/check_api_drift.cs` + `scripts/api_domains.json` — content-based drift gate (regenerates to a temp dir and diffs bytes, not mtimes) | Done |
| 0.4 | `scripts/generate_csharp.cs` — `Classifier` + `CSharpBackend`, covering provider vtables, `[callback]` vtables, free functions, and enums | Done |

Verified end to end on `ke_input` (§8.3) and the `ke_logger`/`ke_logger_sink` callback shape (compile-probed). Not yet done: the tag vocabulary will grow as harder domains surface needs it doesn't cover (§8.4) — Stage 0's infrastructure is stable, its tag *vocabulary* is deliberately open-ended per §8.8.

### 8.3 Stage 1 — pilot domain (`ke_input`) — done

The cheapest possible falsification of the entire strategy. Chosen because it is small, stable, well shaped, and already partly proven. All seven steps landed:

1. **Audit** every file in `src/csharp/input/` against the §4.1 rubric — Appendix A.1.
2. **Resolve LEAKED verdicts** — the snapshot bitset accessors moved into the ABI (`ke_input_snapshot_is_key_down` etc.); `ke_mouse_button` completed from 3 to 8 values to match the managed enum; `ke_input_action` named for the previously-untyped `1`/`0` convention.
3. **Annotate** `input.h`, `event.h`, `key.h`, `snapshot.h`, plus `logger.h` for the callback shape.
4. **Extract** → `src/csharp/input/ke_api.json`, committed.
5. **Generate** the managed layer via `kabic`.
6. **Delete** the hand-written files `kabic` replaced — `Key.cs`, `MouseButton.cs`, `InputReaderExtensions.cs`, `Input.cs`, `InputSnapshotReader.cs`.
7. **Verify** — full solution builds, 124/124 C# tests pass, `zig build` clean.

**Gate held**: the generated layer came out *better* than the hand-written one it replaced — it preserved the `Key` type on `IsKeyDown` (the hand translation had widened it to `int`) and exposed `IsKeyPressed`, which the hand-written wrapper silently omitted despite it existing in the ABI all along.

### 8.4 Stage 2 — roll out, easiest first

Each domain repeats §8.3's seven steps. Order is by ascending leakage and coupling, so the process is well practised before it meets the hard cases:

| Wave | Domains | Why here |
|---|---|---|
| **A** | `window`, `logger`, `scheduler`, `configuration` | Small, stable, thin wrappers, minimal leakage |
| **B** | `ecs`, `asset`, `audio`, `physics`, `text` | Medium; some real leakage expected |
| **C** | `render`, `framework` | Large surface; `WebgpuRenderModule` and `MeshPrimitives` leakage must land first |
| **D** | `toolkit` | Hardest — ~900 lines of services (§12.1 of `ScriptingArchitectureV2.md`), each needing an individual verdict |

Wave D is where the strategy either lands or reveals that a capability genuinely belongs in a managed layer. Do not pre-judge it.

**Wave D result**: `toolkit` (1585 lines across `Scene/`, `Modules/`, `Input/`, `Systems/`, `Text/`, `Assets/`) had zero raw ABI touches — no `ke_*` pointer, no `unsafe` block anywhere in it. Every file reached the kernel exclusively through the wrapper types Waves A–C already produced (`World`, `SceneTree`, `IEcsRegistry`, `IRenderResources`, `NativeInputActions`, ...). There was no vtable here for `kabic` to mechanize — `NodeWorld` (278 lines, the largest file) is the "node access funnel" §8.1 already named as part of the permanent floor: entity/name lookup dictionaries, behavior registration, system-context scoping — genuine Track 4 idiom with no ABI counterpart by design, not leakage waiting to be moved. Wave D closed with **no migration performed**, because there was nothing left in it that Track 3 governs — every domain with a real C ABI vtable (Waves A/B/C, 16 domains total) was migrated; `toolkit` was always downstream of them, never a wrapper layer in its own right.

**2026-08-05 correction: "no migration performed" did not mean "leave it as one project."** `toolkit` being architecturally downstream of every real domain was true and is why Track 3 (kabic) never touched it — but physically bundling five domains' node ergonomics (render's lights/camera/mesh, physics's `CollisionShape2D`, audio's `AudioPlayer`, the framework's own `Node`/`NodeWorld`) into one `KernelEngine.Toolkit` project was itself a leak of the same shape Track 1's rubric exists to catch, just one level up: a domain's ergonomic surface living outside that domain's own project. `src/csharp/toolkit/` is deleted. Every file moved into the project of the domain that actually owns it:

| Old (`toolkit/.../Scene|Modules|Input|Systems|Text`) | New home | Why |
|---|---|---|
| `Node.cs`, `Node2D.cs`, `Node3D.cs`, `NodeWorld.cs`, `View.cs`, `SceneRouter.cs`, `NodeTypeRegistry.cs`, `SceneServiceCollectionExtensions.cs`, `GeneratedNodeComponentAttribute.cs`, `SceneNodesModule.cs`, `SceneRouterModule.cs`, `Input/*` | `KernelEngine.Framework` | Owns `ke_scene_tree`/`ke_world`; no other domain's data |
| `Camera.g.cs`…`AmbientLight.g.cs`, `MeshRenderer.cs`, `Skybox.cs`, `Sprite2D.cs`, `UiQuadComponent.cs`, `Label.cs`, `Font.cs`, `ModelExtensions.cs` | `KernelEngine.Render.Webgpu` | render's own component vocabulary (§7.13) |
| `CollisionShape2D.cs`, `IPhysicsBody2D.cs` | `KernelEngine.Physics` | physics-only data/logic |
| `AudioPlayer.cs` | `KernelEngine.Audio` | audio-only data/logic |

The `LabelUiSystem.cs`/`Systems/` C# text-shaping system moved to `Render.Webgpu` first, then was deleted outright — its logic became a native system inside `ui_module.zig` (see below), which is what §7.6 open question 1 always said this class of code should become.

Two further leaks of the identical "one place hardcodes every other domain's vocabulary" shape were found and fixed while doing this move, mirroring §6.5's `world.zig` correction (below) at the C# layer:

- `NodeWorld` held a hardcoded `List<Label>`/`RegisterLabel` — `Label` is render's node type, `NodeWorld` is framework's. Replaced with a generic `AllNodes` (every bound node); `LabelUiSystem` filtered `OfType<Label>()` itself before it was deleted, and any future per-type consumer does the same.
- `SceneServiceCollectionExtensions.EnsureRegistry` pre-registered every builtin node type (`Camera`, `PointLight`, `AudioPlayer`, `CollisionShape2D`, …) directly in `KernelEngine.Framework`. Removed; each domain's own composition entry point (`WebgpuRenderModule.Configure`, and the equivalent for physics/audio once they have one) calls `services.AddNodeType<T>()` for its own types only.
- `SceneNodesModule.OnLoad` ran render's `[entity.components.AmbientLight]`/`[entity.components.MeshRenderer]` property-apply callbacks and called `LabelUiSystem.Register` directly. Moved into `WebgpuRenderModule.OnLoad`; `SceneNodesModule` now only does what is genuinely domain-agnostic (the `NodeWorld` behavior-dispatch system and the one-shot scene-setup dispatch).

**The native side had the same leak, one layer down, and got the same fix.** `src/zig/framework/src/world.zig`'s `world_create` hardcoded `registerBuiltin` calls for `camera`/`mesh`/`directional_light`/`point_light`/`spot_light` — all render-domain components — and `kernel_engine/framework/components.h` `#include`d `kernel_engine/render/components.h` to get their types. `ke_world.register_component_apply` (a public vtable slot, already existed, was simply unused by anyone but the framework plugin itself) is exactly the extension point meant for this: `ke_render_module_create` gained a `ke_world *world` parameter and now calls `ke_render_register_scene_apply(ecs, world)` (`src/zig/render/service/src/component_apply.zig`, new file) to register its own cids/applies. `world.zig` now registers only `transform` — framework's own, via `scene_tree`. The `render/components.h` include was removed from `framework/components.h`.

**Native UI text shaping moved out of C# entirely.** `ke_label_component` (`ui_create.h`) is a new native component — `font`/`anchor`/`offset`/`color`/`text[256]` as caller input, `glyph_count`/`glyphs[256]` as output. `render.ui`'s own runtime system now shapes each label's glyphs (measuring text, computing anchor/baseline against the real backbuffer size, which is only available inside its own render-pass context — this is why shaping happens as part of `render.ui` itself rather than a separate `KE_PHASE_UPDATE` system) and draws them the same way it draws `ui_quad` entries, sharing the font/glyph tables `ke_render_ui.load_font` already populated. `Label.cs` is now pure data — every property setter writes straight into `ke_label_component` via `SetByCid`. No per-glyph entity, no pool, no C# system.

### 8.5 Stage 3 — acceptance test: a second language

Implement a Lua or Python `kabic` backend plus a runtime shim, consuming the same `ke_api.json`. For a dynamic language this should require **no build-time codegen at all** (§6.2).

**Pass condition**: no native change, no hand-written per-domain wrapper. If either is needed, the strategy has a gap and the gap is now visible with a concrete failing case.

### 8.6 Validation strategy for generated code — required before merge

**Why this is its own stage, not folded into "write tests."** Checked in-session what the existing 95 C# tests (`tests/csharp/KernelEngine.Kernel.Tests/`) actually validate: mostly the hand-written idiom layer's live behavior against the real native runtime (`Physics2DTests`, `TaskSchedulerTests`, `WindowTests`, `HandleTests`), not `kabic`'s codegen correctness. One (`NodeTests.Node_Properties_InitialValues`) is a placeholder tautology (`Assert.Equal(0u, 0u)`) that tests nothing. `src/csharp/kabic/VERIFICATION.md` is real and thorough, but it is a **manual, C#-specific checklist** ("read every method body," `Encoding.UTF8.GetBytes`, C# reserved words) — none of it transfers to Stage 3's second-language backend for free. Writing more hand-written per-domain C# tests from here on, as if they validated `kabic` itself, would misdirect effort the same way the 95 already do: they'd keep testing the shrinking hand-written remainder, not the generator responsible for everything else.

**The fix is separating validation into what is backend-agnostic (pays for every future backend, including Stage 3's) and what is genuinely backend-specific (must be re-derived per backend, but by a repeatable method, not from scratch):**

**Backend-agnostic — invest here first, before Stage 3's second language exists:**

1. **IR-level snapshot tests.** `ke_api.json` is the one artifact every backend shares. A parsing/tag/classification bug is caught once, here, independent of any backend existing yet — committed `ke_api.json` per domain already serves as the fixture; formalize the comparison as an actual test rather than the manual "read the JSON" step in `VERIFICATION.md` §2.
2. **Idempotency.** Generate twice from the same IR, diff must be zero bytes. Done manually this session (every domain regenerated, confirmed byte-identical except intentional changes) and already a manual step in `VERIFICATION.md` §2 — promote it to an automated test. Catches non-determinism (dictionary ordering, etc.), which is a real generator defect class, in every backend uniformly.
3. **Cross-backend structural assertions**, the same technique `AgnosticDriftTests.cs` already uses (scan source text/AST for a structural invariant) pointed at `kabic`'s own output instead of the engine's layers: for every `[node:]`-tagged struct in the IR, does *each* backend's output have exactly one type, with the same property count as fields, matching `[default:]` values? This is checkable without deeply understanding the target language — counting declarations, not evaluating semantics — so it is the one category that literally runs unmodified against a Python or Lua backend the day it exists.

**Backend-specific — the method generalizes, the checklist text does not:**

4. **"Does it compile," using that backend's own toolchain, as the cheapest per-backend gate.** `dotnet build` today; `python -m py_compile` / `mypy` for a Python backend later. Weak alone, but free — no test-writing, and it already catches a large defect class in every language it's run against.
5. **A `VERIFICATION.md`-shaped manual checklist stays necessary per backend**, because idiom concerns are genuinely language-specific (C#'s UTF-8 marshalling prologue has no Python equivalent, Python will have its own). What transfers is the *method* — read every slot shape (`Plain`/`Fallible`/`Try`/...) once per combination that backend has never rendered before, not once per domain — not the checklist's text.
6. **Runtime/integration tests stay minimal by design**, mirroring what this session already did rather than growing per domain: a handful of pilot domains proving the pipeline end-to-end (`PointLight`, `ke_input`'s Stage 1), not a hand-written test suite re-proving every migrated domain individually. This is the corrective for the 95-test pattern above — the count should stop growing as a proxy for coverage.

**Gate for merge**: items 1-3 exist as automated tests (not manual checklist steps) before this branch merges — they are the ones that pay off for Stage 3 (§8.5) without being rewritten, so deferring them past merge means Stage 3 starts with the same "no oracle beyond the header" problem `VERIFICATION.md`'s own opening line already names, except now for a language nobody has looked at yet.

**Status as of 2026-08-05: still not paid.** Items 1-3 do not exist as automated tests — `tests/csharp/KernelEngine.Kernel.Tests/AgnosticDriftTests.cs` is a different check (the hand-written idiom layer vs. the ABI, not `kabic`'s own codegen). `NodeTests.Node_Properties_InitialValues`'s `Assert.Equal(0u, 0u)` placeholder, named above, is also still in the tree, unchanged. §7.13 generalized the node-ergonomics pilot to 5 domains without this gate being met first — a gap opened, not closed, by that work; paying it off is the highest-leverage next step under this document's own terms, since every domain generation since `PointLight` has been validated by hand (build + run + read the diff) rather than by an oracle that would catch a regression automatically.

### 8.7 Stage 4 — Node ergonomics (Track 4)

Last, and only now, because it registers into an ABI that Stages 1–2 are still reshaping. Lifecycle-host design in `ScriptingArchitectureV2.md` §4/§5; the generated-node-type design, its open questions, and its pilot gate are in §7.1–§7.8 above.

### 8.8 Invariants held throughout

- **No big bang.** Each domain lands independently; the build and every example stay green between domains.
- **Generated code is never edited.** Same rule that already governs `Native/Generated/`.
- **`ke_api.json` is an output.** Regenerated from headers, committed only so the drift check has something to compare against.
- **Deletion is the deliverable.** A domain is not done when `kabic` produces output — it is done when the hand-written files it replaces are gone.

---

## 9. What will never generate — the honest floor

Per language, permanently hand-written:

- **Language-runtime plumbing** — GC/handle lifetime, callback trampolines and pinning, exception or error-value translation, crash/signal handling (`Common/CrashHandler.cs`, 258 LoC in C#). Roughly 300–400 LoC. Does not grow with API surface.
- **The composition idiom** — C# uses `IServiceCollection`; Python would use context managers; Lua a table. The *bindings* generate, the idiom is a choice.
- **The node access funnel** — a hook body needs a scoped handle to the world. C# calls it `View`; the Zig spike independently grew `NodeApi` for the same reason. Inherent, small, not a C# artifact.
- **A composition root** — the Zig spike's `main.zig` is 233 lines of device/window/ecs/runtime/render/physics setup against 144 lines of actual game logic. Thin scripts do not imply a thin host. Reducing this is a separate concern (a native default-host / bootstrap), not a binding concern.

**The floor is not the target — zero-per-domain is (§1.1).** The floor is a constant paid once per language; the per-domain cost is what would otherwise multiply. Adding the fifteenth domain must cost zero hand-written lines; adding the second language costs this floor once.

**The floor's size is an estimate, not a measurement.** It is inferred from the C# baseline (`CrashHandler` 258, error types 133, ten `ServiceCollectionExtensions` totalling 411). Only an actual second language measures it. Treat any figure quoted here as provisional until §8.5 runs.

---

## 10. Non-goals

- **ABI versioning / method hashes.** Godot needs them because compiled extensions must survive engine updates. Everything here builds together from one tree. Revisit only if precompiled third-party plugins ship against a different engine version than they run on.
- **A runtime reflection registry.** Godot's `ClassDB` exists for dynamic name-based dispatch; our vtables are static. Not needed (§5.3).
- **Replacing the C ABI.** It is the narrow waist and it stays. Every track here makes it more complete or more describable — none replaces it.
- **A serialized IR for user-declared types.** Rejected with reasons in `ScriptingArchitectureV2.md` §9.2. The same rule applies throughout this document: serialized artifacts are outputs (`ke_api.json`, generated sources), never hand-authored inputs.
- **Python/Lua SDKs before the acceptance test is deliberately scheduled.**

---

## 11. Open questions

- **Tag vocabulary and syntax inside `@param`.** `[array:4]`, `[borrowed,utf8]`, `[out,nullable]` is the shape proven in §5.2; the exact set and spelling is the step-1 deliverable. Resolved already: it rides in doc comments, not in attributes (§5.1) and not in a sidecar.
- **Export macros.** There are 28 distinct `KE_<PLUGIN>_API` macros, each repeating the same four-branch `dllexport`/`dllimport`/`visibility` block, alongside a general `KE_EXPORT` in `common/export.h`. The per-plugin split exists because `dllimport` vs `dllexport` depends on a per-plugin "am I building this?" define — a standard pattern, not dead code. But with Zig as the only toolchain and exports declared Zig-side, whether 28 macros can collapse to one is worth checking. **Not blocking**: `kabic`'s frontend ignores them, or uses them to identify exported factories. Its own cleanup card.
- **How idiomatic can generation get before it needs hints?** Some conversions (a paired `T*` + `count` into a `Span<T>`) are mechanical; others (should `try_get` return a tuple, a nullable, or throw?) are taste. Likely a small per-slot hint vocabulary layered on §5.1 — but do not design it speculatively; let step 3 surface what is actually needed.
- **Do the `*.Abstractions` interface projects survive?** ~400 LoC of `IEcs`/`IWorld`/`IInput`/`ISystem` exist for DI and testing. If the concrete generated type is already thin, the interface may be pure ceremony. Decide during step 3.
- **Where does the composition root go?** §9 names it as a floor, but a native bootstrap ("give me a window + gpu + ecs + runtime + render with sane defaults") would shrink it for every language at once. Out of scope here; worth its own card.
- **ClangSharp is a kept dependency, not scheduled for removal — do not reimplement it.** Checked in-session: even the 16 domains `api_domains.json` already lists as migrated still carry their ClangSharp `.rsp` and `Native/Generated/*.g.cs` (25 `.rsp` files, 222 generated files, present), and this is correct, current-state, not debt. `kabic` only replaces the *ergonomic* wrapper layer — providers, callbacks, enums, node types — sitting on top of the raw struct/delegate declarations ClangSharp still emits; `PointLight.g.cs` itself directly uses `ke_point_light_component`, a ClangSharp-produced type, today and for the foreseeable future. The two generators coexist by design, and `kabic` depends on ClangSharp's output — it is not redundant with it. There is a theoretical future where `kabic`'s own frontend (it already parses the same clang AST via `extract_api.cs`) could emit the raw layer too and retire ClangSharpPInvokeGenerator, and *if* that is ever deliberately taken on, there would be no obligation to keep mirroring ClangSharp's `Native/Generated/` directory shape or its per-project `.rsp` convention. But that is speculative, unscoped, and explicitly **not planned** — recorded here only so a future reading of this document does not mistake "ClangSharp could theoretically be replaced" for "ClangSharp is being replaced" and start reimplementing binding generation that is not needed.

---

## 12. Summary

| Track | Fixes | Baseline it removes | Priority |
|---|---|---|---|
| 1 — Completeness | Engine capability above the ABI | ~900 (Toolkit services) + unblocks every other language | **Blocking prerequisite**, per domain (§4) |
| 2 — Describability | Headers carry syntax, not semantics | Enables all of Track 3; moves 1 793 doc lines to the ABI | After 1, per domain |
| 3 — Derivation | Wrappers written by hand | ~3 600 of the 5 195 | After 2, per domain |
| 3a — shared classification | Each backend re-deriving slot semantics, and diverging | — | Once (§6.1) |
| 3b — per-language backend | Seven rendering decisions + shim | — | Once per language (§6.2) |
| 4 — Node ergonomics | Registration mechanics per language | ~600 | Last (§8.7) |

Tracks 1→2→3 are not phases across the project; they are the **order within each domain**, repeated domain by domain per §8.4.

The answer to *"can a GDExtension-style strategy remove the hand-written per-domain layer?"* is: **yes — but generation only removes the cost of *writing* the idiom, never the need for it (§0/§2), and it does not reach capability that leaked above the ABI.** Track 1 is the load-bearing one even though Track 3 is what shows up in the line count.

---

## Appendix A — Domain audits (Track 1, §4.1)

Each domain's audit table lands here as it is completed. Verdicts per §4.1: MECHANICAL (`kabic` replaces it), LEAKED (capability must move below the ABI), IDIOM (stays, must be in the §9 floor), DEAD (delete).

### A.1 — `input` (615 hand-written LoC) — audited, cleared for Track 2

| File | LoC | Verdict | Note |
|---|---|---|---|
| `Abstractions/Input/Key.cs` | 130 | **DEAD** | 121 entries duplicating `key.h`'s 121, maintained by hand |
| `Abstractions/Input/MouseButton.cs` | 17 | MECHANICAL | Enum mirror |
| `Abstractions/Input/ActionType.cs` | 30 | MECHANICAL | Enum mirror (`ActionType` + `ActionPhase`) |
| `Abstractions/Input/InputEvent.cs` | 45 | MECHANICAL | Mirror of `ke_input_event_kind` — **drops `MOUSE_MOVE = 5`** |
| `Abstractions/Input/InputReaderExtensions.cs` | 12 | **DEAD** | Exists only to re-add the `Key` type that hand translation discarded |
| `Abstractions/IInput.cs` | 22 | MECHANICAL | Interface over the vtable |
| `Abstractions/Input/InputActionEvent.cs` | 95 | IDIOM (review) | `System.Type` + generic `Is<T>`/`As<T>`; no native counterpart |
| `Abstractions/IInputReader.cs` | 30 | IDIOM | Managed abstraction over the snapshot struct |
| `Abstractions/InputContext.cs` | 23 | IDIOM | `[ThreadStatic]` ambient accessor |
| `Input/Input.cs` | 130 | MECHANICAL (~70) + IDIOM (~45) | See note below on `DrainEvents` |
| `Input/InputSnapshotReader.cs` | 36 | **LEAKED** | Replicates the snapshot's bit layout — see below |
| `Input/ServiceCollectionExtensions.cs` | 16 | IDIOM | DI registration |
| `Input/INativeInput.cs` | 13 | **MECHANICAL** (corrected — see below) | Cross-domain pointer accessor; `kabic` now generates this shape |

**Outcome**: ~375 of 615 lines generated or deleted (61%); ~165 IDIOM, all within the §9 floor. **One LEAKED verdict must land before the domain is cleared for Track 2.**

#### LEAKED: `InputSnapshotReader` replicates the ABI's bit layout

`IsKeyDown` reimplements the snapshot encoding in the consumer:

```csharp
if (keyCode < 0 || keyCode >= 512) return false;
return (_data.keys_down[keyCode / 64] & (1UL << (keyCode % 64))) != 0;
```

The `512`, the word/bit split, the shift — none of it is inferable from `uint64_t keys_down[8]`; it exists only in a prose comment in `snapshot.h`. Every language would rewrite it, and would silently break if the encoding changed.

**Fix (Track 1)**: the snapshot is a value struct passed across threads, so it has no vtable to carry behaviour. Add free accessors to the ABI, which doctrine already permits for kernel built-ins (precedent: `ke_mesh_is_valid`, `ke_material_is_valid`):

```c
bool ke_input_snapshot_is_key_down(const ke_input_snapshot *s, int32_t key);
bool ke_input_snapshot_is_key_pressed(const ke_input_snapshot *s, int32_t key);
bool ke_input_snapshot_is_key_released(const ke_input_snapshot *s, int32_t key);
/* and the mouse-button equivalents */
```

`InputSnapshotReader.cs` disappears entirely and the losses below are closed as a side effect.

Precisely: the packing does **not** become private — `ke_input_snapshot` crosses the ABI by value, so its layout is public whether or not accessors exist. What the accessors provide is the single *canonical* decode, so no consumer has to re-derive it and none silently breaks if the packing changes. The same reasoning gave the constants (`KE_INPUT_MAX_KEYS`, `KE_INPUT_KEY_WORDS`) names in the header instead of leaving them as prose.

**Why not a `[bitset:512]` tag (Track 2)?** A tag would make every language's `kabic` backend emit the shift, keeping the encoding a public contract that every binding replicates. The rule: *a tag describes what the C type cannot say; it is not a way to publish an internal detail that should not be public.*

**Three ABI-surface losses found, all silent:**

1. `ke_input.is_key_pressed` exists in the vtable and is absent from the managed surface entirely.
2. `KE_INPUT_EVENT_MOUSE_MOVE = 5` exists in `ke_input_event_kind`; `InputEventKind` jumps from 4 to 6.
3. `keys_pressed`, `keys_released`, `mouse_buttons_pressed`, `mouse_buttons_released` exist in `ke_input_snapshot` and are exposed by nothing — unreachable from any language.

None was detectable by any test. All three close once the enum, the vtable, and the snapshot accessors are generated.

**Audit lesson.** `InputSnapshotReader` was first classified MECHANICAL because it *looks* like forwarding — short, and it only reads fields. It computes. Apply §4.1's test literally rather than judging by shape: **does this file compute, decide, or store anything?** If yes, it is LEAKED regardless of how thin it looks.

**Second audit correction (found migrating `window`, §8.4).** `INativeInput.Native` was first classified **DEAD**, reasoned from a stale memory note calling the `INativeX.Native` pattern doctrine-rejected. It is not dead: `window.glfw`'s `ServiceCollectionExtensions` consumes it to pass `Input`'s raw pointer into `ke_window_glfw_params`, and the identical `INativeX { ke_x* Native { get; } }` shape is already load-bearing in twelve other domains (`INativeLogger` alone: Audio, Assimp, StbImage, Physics.Box2D, WebgpuRenderModule, Text.StbTrueType, Window.Glfw). This is the project's actual, established answer to cross-domain composition wiring — `InternalsVisibleTo` is banned because it requires the *producer* to enumerate every consumer (the inversion of the inversion this project's DI doctrine exists to prevent); a public `Native` accessor on the wrapper lets any consumer opt in without the producer knowing who they are. Corrected verdict: **MECHANICAL** — the shape is so repeated and boilerplate that `CSharpBackend` now generates it for every provider (§6.2 update).

**Third finding — a duplication comment that already rotted.** `key.h` states *"The managed-side mirror lives in KernelEngine.Kernel.Abstractions/Input/Key.cs"*. That project no longer exists; the file is in `KernelEngine.Input.Abstractions`. A hand-maintained mirror whose own pointer to its twin has gone stale is the argument for generation in one line.

**`DrainEvents` reclassified from LEAKED to IDIOM.** `ke_input_event` is already flat and complete; the managed reshape into a `Kind`-discriminated union adds accessors, not capability, so no engine capability is trapped in C#. Noted with a caveat: `event.h` justifies its flat layout as being *"for friction-free C# P/Invoke binding"* — an ABI shaped around one consumer. Harmless here, but the pattern is worth watching in later domains.

### A.2 — `window` (221 hand-written LoC) — audited, migrated, cleared

| File | LoC | Verdict | Note |
|---|---|---|---|
| `Window/Window.cs` | 64 | **MECHANICAL** | Provider vtable wrapper; deleted, generated |
| `Window/INativeWindow.cs` | 13 | **MECHANICAL** | Same `INativeX` shape as `input`'s A.1 correction; deleted, generated |
| `Window.Abstractions/IWindow.cs` | 9 | IDIOM | Hand-authored interface `kabic` doesn't know about; kept via a zero-logic `partial class Window : IWindow` marker (`Window.Idiom.cs`) — the generated members already match its shape 1:1 |
| `Window.Glfw/GlfwWindowModule.cs` | 58 | IDIOM | `IRuntimeModule`/DI composition — inherent to how *this* language expresses composition |
| `Window.Glfw/ServiceCollectionExtensions.cs` | 73 | **LEAKED, deferred** | See below |

**Outcome**: both MECHANICAL files deleted and generated; `Window.g.cs` + a 9-line idiom marker replace 77 hand-written lines. Full solution builds, 124/124 tests pass, `zig build` clean.

**LEAKED, deferred**: `ServiceCollectionExtensions.AddGlfwWindow()` reads `[runtime.window] width/height/title/fullscreen` from the Project file with C#-literal fallback defaults (`1280`, `720`, `"KernelEngine"`, `false`). Confirmed in `glfw_window.h`: `ke_window_glfw_params` has no "unset" sentinel — the native factory has zero default-selection logic of its own, identical in shape to the already-flagged `WebgpuRenderModule` leak (§4). A Lua game wanting the same "override else sane default" behavior would reimplement this from scratch. **Not resolved here**: it is the same underlying design question as `WebgpuRenderModule`'s leak (should `ke_configuration`-driven default resolution move natively, for every module, as one mechanism?) and deserves one unified decision, not two independent one-off patches. Recorded per §4.2's explicit-deferral allowance.

**Three `kabic` extensions this domain forced, all now general (not window-specific)**:

1. **Multiple `[out]` parameters → tuple return.** `get_size(int32_t *width, int32_t *height, ke_error **out_error)` didn't fit the existing single-`[out]`-param shape (§6.1's `ReturnsOutParam`). Added `SlotShape.TupleOutParams`: N-or-more same-slot `[out]` params with nothing else public render as `(T1 Name1, T2 Name2, ...)`. Purely a classification/rendering addition — no new tag.
2. **`[lifecycle:init]` / `[lifecycle:shutdown]` tags.** `ke_window`'s `on_initialize`/`on_shutdown` must run automatically (once, right after construction; once, right before destroy) rather than be exposed as ordinary callable methods — a shape the existing tag vocabulary had no name for. The tag rides in the *slot's own summary*, not inside an `@param` — the same `[bracket]` convention extended one level, not a new mechanism. `CSharpBackend` wires the tagged slot into the generated constructor/`Dispose` and excludes it from the public method list.
3. **`[sink]` tag, replacing a naming-convention heuristic.** The pre-existing `on_`-prefix skip rule (written for `input`'s `on_key`/`on_mouse_move`/etc.) happened to also catch `on_initialize`/`on_shutdown` by coincidence — two unrelated concepts sharing one fragile string match. Replaced with an explicit `[sink]` tag on `input.h`'s four sink slots; the skip condition is now `Has("sink") || Has("lifecycle")`, no name-prefix matching anywhere in the generator.
4. **A fourth provider shape: construction from a bare `ke_X_handle`, no factory of its own.** `ke_window` has no `ke_window_create` — any backend (GLFW, ...) hands back a `ke_window_handle` and construction is generic over that handle. `RenderProvider` now falls back to a `public {Type}({Type}_handle handle)` constructor when no matching `_create` function exists but a `_handle` struct does. **Public, not `internal`** — unlike the factory-parameter case, a `ke_X_handle` is a plain managed-visible value type this wrapper itself owns the shape of, not a raw pointer into a sibling native namespace, so no idiom-layer wrapper is needed to make it callable across assemblies.

**Two generator bugs this domain's regeneration caught, fixed before commit**: tuple-out param types weren't dereferenced (`int32_t * Width` instead of `int Width`); an opaque `void *` return (`get_native_handle`) rendered as a raw unsafe pointer instead of the `nint` idiom the hand-written code already used. Both confirmed against the original hand-written `Window.cs` byte-for-byte in shape after the fix.

### A.3 — `logger` (244 hand-written LoC) — audited, migrated, cleared

| File | LoC | Verdict | Note |
|---|---|---|---|
| `Logger/Logger.cs` | 118 | Split: MECHANICAL (vtable forwarding, `INativeLogger`) generated; string marshaling + `Trace`/`Debug`/.../`Critical` convenience + `ILoggerSink` adapter kept as `Logger.Idiom.cs` | |
| `Logger/INativeLogger.cs` | 13 | **MECHANICAL** | Same `INativeX` shape; deleted, generated |
| `Logger/ConsoleSink.cs` | 25 | **LEAKED, fixed** | See below |
| `Logger.Abstractions/LogLevel.cs` | 16 | **MECHANICAL** | Mirrors `ke_log_level`; deleted, generated from `log_level.h` |
| `Logger.Abstractions/ILogger.cs` (`ILogger`+`ILoggerSink`) | 27 | IDIOM | Hand-authored game-facing interfaces; `Logger` declares conformance via `Logger.Idiom.cs`, no marker file needed since it already carries real logic |
| `Logger/ServiceCollectionExtensions.cs` | 43 | IDIOM, rewritten | Now builds sinks from the native factory instead of the deleted `ConsoleSink`; a separate, unrelated wiring bug found here (below) |

**Outcome**: `Logger.cs`/`INativeLogger.cs`/`ConsoleSink.cs`/`LogLevel.cs` deleted (172 lines); `Generated/Logger.g.cs` + `Generated/LoggerSinkNative.g.cs` + `Generated/LoggerSinkFunctions.g.cs` + `Generated/Enums.g.cs` (generated) + `Logger.Idiom.cs` (58 hand-written lines: string marshaling, six severity-named convenience methods, the `ILoggerSink`→`ILoggerSinkNative` adapter) replace them. Full solution builds, 122/122 C# tests pass (one deleted — `ConsoleSinkTests.cs`, which asserted C#-side formatting logic that no longer exists), `zig build` clean, native probe confirms the new console sink's output matches the old one byte-for-byte.

**LEAKED, fixed**: `ConsoleSink.cs`'s own doc comment claimed to mirror *"the native `ke_console_sink`"* — which did not exist. It also hand-maintained a level-name table (`"CRIT"` for critical) that had already drifted from the native `ke_log_level_to_string("CRITICAL")`. Every language wants a stderr sink with a stable format; fixed natively:

- `ke_console_sink_create()` added to `logger.h`, implemented in `logger_simple.zig` (`fprintf`/`fflush` via libc — Zig 0.16 moved file IO behind an `std.Io` instance this plugin has no reason to plumb through, matching the same call the project's own `configuration_toml.zig` already makes for the identical reason).
- Verified with a standalone C probe before any C# work: `[INFO] test: hello from console sink`, matching the old hand-written format exactly.
- `ServiceCollectionExtensions.cs` rewritten to build sinks from the native factory (`NativeConsoleLoggerSink`, wrapping the raw value behind `ILoggerSink` for the existing DI registration shape) instead of reimplementing formatting.

**Unrelated bug found, not fixed here, flagged separately**: nothing in the codebase ever resolves `ILoggerSink` from the DI container and calls `logger.AddSink(sink)` on it — `AddConsoleSink()` has registered a sink that's never attached, in every one of the 22+ examples that call it, since before this migration. Preserved as-is (same registration shape, same non-consumption) to avoid an unrelated behavior change mid-migration; a follow-up task was spawned instead of fixed inline.

**Two `kabic` extensions this domain forced, both now general**:

1. **A "value factory" shape**: a free function producing a `[callback]`-classified vtable *by value*, with no owning first-parameter (`ke_console_sink_create() -> ke_logger_sink`) — distinct from the existing "operation on a value type" free-function shape (`ke_input_snapshot_is_key_down(snapshot, key)`), which takes the owner *by reference* as its first argument. `Classifier` now also groups a free function by its *return* type when no param matches an owner; `RenderFreeFunctions` renders either shape correctly (with or without a `self` parameter) from the same file.
2. **`AddSinkRaw`**: a callback slot (`add_sink`) now also gets a second, raw overload that forwards an already-built callback-vtable value straight through, with no `GCHandle`/trampoline wrapping — for a value that came from a native factory (case 1) rather than a managed implementation of the generated interface.

**Two more `kabic` bugs found and fixed while regenerating**:

1. **The factory constructor was unconditionally `internal`.** The rule ("raw pointer params from a sibling native namespace need an idiom-layer public wrapper") doesn't apply to a factory with no such param — `ke_logger_create()` takes nothing but the trailing error param, so `public Logger()` needed no idiom-layer wrapper at all. `RenderProvider` now checks whether any factory param is actually a pointer before marking the constructor `internal`; retested against `input` (factory takes `ke_logger*`, stays `internal`, unaffected) and `window` (no factory, unaffected).
2. **A missing `using System.Runtime.CompilerServices;`** in the provider template — never surfaced before because `logger` is the first domain whose *provider* (not just its standalone callback-interface file) also contains a `[callback]`-classified slot rendered inline, needing `CallConvCdecl` in the same file.

**A free function found but deliberately not wired**: `ke_log_level_to_string(int32_t level)` doesn't fit any current grouping rule — its single parameter is a bare `int32_t`, not one of this domain's own structs, so it has no natural "owner" to attach to. Left unexposed rather than inventing a placement for it; nothing currently needs it now that the native console sink calls it internally. `Classifier` was tightened alongside this fix to only group free functions by first-param type when that type is one of the domain's own known structs — it had been grouping by *any* first-param type, which briefly misfired by grouping this function under a spurious `Int32T` bucket.

### Note — kabic promoted from a 914-line script to real projects

`scripts/generate_csharp.cs` had grown to 914 lines and, on inspection, had started re-deriving decisions inline (constructor shape, callback `min_level` presence, free-function "self" detection) instead of reading them from `ClassifiedModel` — the exact drift §6.1/§6.2's separation exists to prevent, just subtler than the original §5.5 prototype's version of the same mistake.

Fixed two ways at once:

1. **Every such decision moved into `Classifier`**, computed once: `ConstructorPlan` (factory vs. handle vs. none, and whether the factory ctor needs an idiom wrapper), `CallbackHasLevel`, and `GroupedFunction.SelfParam`. `CSharpBackend` now only reads these; it does not re-derive them from raw `ApiFunction`/`ApiStruct` shapes anywhere.
2. **kabic moved from `scripts/*.cs` file-based apps into real projects under `src/csharp/kabic/`**, next to every other real C# project in the repo (`KernelEngine.Input`, `KernelEngine.Window`, ...), added to `KernelEngine.slnx`:
   - `Kabic.Core` — the middle-end: `ApiModel`/`ApiReader` (the IR reader), `Classifier`/`ClassifiedModel` (§6.1), `CTypes` (pure C-type string operations — `IsPointer`/`Deref` — needed by every backend, not a C# idiom).
   - `Kabic.CSharpBackend` — the backend: `Idioms` (C#-only naming/type-mapping conventions) and `CSharpBackend` (the `Render*` methods), referencing `Kabic.Core`.
   - `scripts/generate_csharp.cs` stays a thin CLI shell (`#:project ../src/csharp/kabic/Kabic.CSharpBackend/Kabic.CSharpBackend.csproj`, ~100 lines: argument parsing and file-writing orchestration only) — the `dotnet run scripts/generate_csharp.cs` invocation is unchanged.

A future Lua/Python/Zig backend is a sibling project referencing `Kabic.Core` the same way — it cannot access anything `Kabic.CSharpBackend`-specific even by accident, because it is a different assembly. Verified byte-for-byte identical output against the pre-refactor generator for all three migrated domains; full solution builds, all tests pass, `check_api_drift.cs` clean.

### Note — kabic's frontend promoted too, and a real bug found doing it

`scripts/extract_api.cs` had the same disease from a different angle: it defined its **own copy** of `ApiParam`/`ApiSlot`/`ApiEnum`/`ApiStruct`/`ApiFunction`/`ApiModel` — parallel to `Kabic.Core`'s, hand-kept in sync as the write side of `ke_api.json` while `Kabic.Core.ApiReader` is the read side of the exact same file. They had **already diverged**: `ApiEnumValue.Value` was `object` (`long` or `string`) in the extractor's copy, `RawValue: string` + `IsInt: bool` in `Kabic.Core`'s. Only luck (both encode/decode consistently to the same JSON shape) kept it working.

Fixed by promoting the frontend the same way: `src/csharp/kabic/Kabic.Frontend/` (`DocParser`, `DeclText`, `Extractor`, `Serialization` — the last one new, since only the write side needs `ToJson()`; nothing that only *reads* `ke_api.json` needs it, so it doesn't belong in `Kabic.Core`), referencing `Kabic.Core.csproj`, using its model types directly. `scripts/extract_api.cs` is now a ~160-line CLI shell: argument parsing, `zig` resolution, and the `zig cc` process invocation (environment/tooling concerns that don't belong in a reusable library) calling into `Kabic.Frontend`.

Two dead methods found and deleted while moving code, not before: `DocParser.SplitTagsSingle` and `DeclText.FreeFnParamNames` — each had exactly one reference, its own definition.

Verified byte-for-byte identical `ke_api.json` output against the pre-refactor extractor for all three migrated domains; full solution builds, all tests pass, `check_api_drift.cs` clean.

### A.4 — `scheduler` (301 hand-written LoC) — audited, migrated, cleared

| File | LoC | Verdict | Note |
|---|---|---|---|
| `Scheduler/Scheduler.cs` | 160 | Split: MECHANICAL (`wait`/`is_completed`/`get_num_workers`, `INativeScheduler`, handle ctor) generated; Task/GCHandle async bridging kept as `Scheduler.Idiom.cs` | See `[raw_callback]` below |
| `Scheduler/INativeScheduler.cs` | 13 | **MECHANICAL** | Same `INativeX` shape; deleted, generated |
| `Scheduler/KernelTask.cs` | 50 | IDIOM | `Task`-shaped awaitable wrapper; no ABI counterpart in any form |
| `Scheduler.Abstractions/IScheduler.cs` | 19 | IDIOM | Hand-authored game-facing interface |
| `Scheduler.Enki/EnkiScheduler.cs` | 31 | IDIOM | Backend factory wiring — see the inheritance finding below |
| `Scheduler.Enki/ServiceCollectionExtensions.cs` | 24 | IDIOM | DI composition |

**Outcome**: `Scheduler.cs`/`INativeScheduler.cs` deleted (173 lines); `Generated/Scheduler.g.cs` (generated) + `Scheduler.Idiom.cs` (117 hand-written lines: the four `[UnmanagedCallersOnly]` trampolines, `Dispatch`/`Dispatch<T>`/`DispatchPinned`/`DispatchKernelTask` Task-bridging, and the `NumWorkers` property) replace them. Full solution builds, 122/122 C# tests pass, `zig build` clean.

**A real `kabic` bug found before generating anything**: `EnkiScheduler : KernelEngine.Scheduler.Scheduler` — a genuine subclass, inheriting the base wrapper to layer its own native construction on top. `RenderProvider` marked every generated class `sealed` unconditionally; had it been generated as-is, this domain would not have compiled. Fixed by dropping `sealed` from the template — the C ABI says nothing about whether a managed wrapper should be inheritable, so imposing it was a restriction `kabic` invented with no basis in the description. Re-verified `input`/`window`/`logger` after the fix: only the `sealed` keyword changed in each, nothing else, confirming the fix has no other effect.

**A new tag, `[raw_callback]`, for the shape this domain introduced**: `dispatch`/`dispatch_on_complete`/`dispatch_pinned` take a bare C function-pointer *parameter* (`ke_task_func`, `ke_task_on_complete_func`) directly — not a `[callback]`-tagged vtable passed by value like `ke_logger_sink`. Unlike the vtable-callback case, there is no ABI-derivable answer to "what should the C# surface look like" here: the value a caller actually wants (`Task`, a coroutine, a plain callback registration — whichever idiom the target language uses for async) cannot be inferred from a bare function pointer and a `void*` context the way `[callback]`'s trampoline shape can be. `[raw_callback]`-tagged slots are therefore excluded from generation entirely (joining `[sink]`/`[lifecycle]` in `RenderProvider`'s skip list) and left whole to the idiom layer, which calls the slot directly through the generated `Handle` property.

**Tooling gotcha hit while verifying the `sealed` fix, worth recording**: `dotnet run scripts/generate_csharp.cs` (a `#:project`-referencing file-based app) caches its build under `~/.local/share/dotnet/runfile/<hash>/`, keyed off the *entry script's* content — editing a `#:project`-referenced file (i.e. anything in `Kabic.Core`/`Kabic.CSharpBackend`) does not reliably invalidate that cache. Regenerating after a kabic code change produced stale output twice in a row despite the referenced project rebuilding correctly on its own; only clearing `~/.local/share/dotnet/runfile/generate_csharp-*` (or `extract_api-*`) fixed it. Byte-diff the output after any kabic change that should have visibly altered it — don't trust a clean run alone.

### 6.5 — `Convention`: the ABI vocabulary, isolated (parameterization is deferred debt)

`kabic`'s classifier knew KernelEngine by name. Six rules were inlined as string literals across `Classifier` and the C# backend: the `ke_` symbol prefix, `_handle` as the owner-wrapper suffix, `_create` as the factory suffix, `ke_error**` as the fallibility marker, `bool`/`_Bool` as the success return. None of these are properties of C — they are one project's vocabulary. A reader could not tell a structural inference (*a vtable is a struct holding function pointers* — true of any C ABI) from a project-specific spelling (*a trailing `ke_error**` means fallible* — true only here), and the compiler was silently coupled to its only consumer's identity.

They are now one `Convention` class in `Kabic.Core`, threaded through `Classifier` and the backend as a parameter, with a single hardcoded `Convention.KernelEngine` instance supplying today's values. Verified byte-for-byte identical output across all four migrated domains — purely structural.

**The remaining debt, deliberately not paid yet**: `Convention` is still a hardcoded instance rather than a per-project input. The intended end state is the M×N shape §9.2 of `ScriptingArchitectureV2.md` established this project *isn't* (M languages × 1 ABI) but that `kabic` itself *is* (M projects × N languages): a `kabic` core knowing nothing about any specific ABI, plus a thin per-project definition supplying a `Convention`.

**Shape of that per-project definition, when it's paid**: not a second hardcoded C# class per consumer (`Kabic.KernelEngine`, `Kabic.SomeOtherEngine`, ...) — that only relocates the coupling §6.5 exists to remove, one file per project instead of one field. The precedent already in this repo is the ClangSharp `.rsp` file (`src/csharp/*/Native/*.rsp`): a per-binding, declarative, non-code input controlling what a code-generation tool does, versioned next to the project it describes. `Convention` should follow that shape — a `.toml` file (`kabic.toml` or similar, read the same way `ke_configuration_toml` already reads project config elsewhere in the engine) supplying `symbol_prefix`, `handle_suffix`, `factory_suffix`, `component_suffix`, the error/boolean spellings, and the type-name override table — instead of a compiled `Convention.KernelEngine` instance. `kabic` becomes an engine with zero compiled knowledge of any consumer; a new project adding `kabic` support ships a `.toml`, not a C# file.

Not done now because the split's shape can't be validated from one data point — a second real consumer is what reveals which axes genuinely vary, and inventing that shape blind risks getting it wrong in a way that's worse than the coupling. **Scheduled for the end of this branch**, and it is debt with a date rather than speculation: the engine is slated for a rename, which forces this refactor regardless — every domain migrated in the meantime only makes it more expensive.

### A.5 — `ecs` (473 hand-written LoC) — audited, migrated, cleared

| File | LoC | Verdict | Note |
|---|---|---|---|
| `Ecs/EcsRegistry.cs` | 86 | Split: MECHANICAL (every vtable slot) generated; the generic span accessors kept as `EcsRegistry.Idiom.cs` | See below |
| `Ecs/INativeEcs.cs` | 13 | **MECHANICAL** | Same `INativeX` shape; deleted, generated |
| `Ecs/VariantReader.cs` | 174 | IDIOM | Managed reader over `ke_variant`; a separate domain concern, untouched |
| `Ecs.Abstractions/*` (`IEcs`, `IEcsRegistry`, component structs) | ~150 | IDIOM | Hand-authored interfaces and managed component mirrors |
| `Ecs.Flecs/FlecsEcs.cs` | 33 | IDIOM | Backend factory wiring |

**Outcome**: `EcsRegistry.cs`/`INativeEcs.cs` deleted (99 lines); `Generated/EcsRegistry.g.cs` + `EcsRegistry.Idiom.cs` (56 lines: the `Span<T>`-returning generic accessors) replace them. The idiom half is irreducible — the ABI trades in `void*` plus an element size, and turning that into `Span<T>` with `T` supplying its own size is a C# generics trick with no ABI counterpart.

Two dead internals found and dropped while migrating: `AddComponentRaw<T>` and `GetComponentRaw<T>`, each with exactly one reference — its own definition.

**This domain broke `kabic` in four separate ways**, all invisible until an ABI this shape hit it:

1. **The sequence shape generated nonsense.** `query_resolve(query, out_segments, max_segments, out_count)` emitted `(uint)span.Length` once per *other* parameter — three times in one call. It also hardcoded the return as the written count, true for `drain_events` but false for `query_register`, which returns a query id. Rewritten: the count parameter is identified *by name* from its own `[array_of:name]` tag and removed from the public signature; every other parameter stays as declared; remaining `[out]` params become C# `out`; the return type is whatever C declares.
2. **`bool` did not always mean "succeeded".** `component_lookup` returns `false` for *"no component by that name"* — a normal outcome to branch on, which the fallible rule turned into a thrown exception. Nothing in the C signature distinguishes the two cases, so the header now says so with `[try]`, rendering `bool TryX(..., out T)`.
3. **String parameters were unusable.** `const char *name` rendered as a raw `char*` no managed caller could supply. The `[utf8]` tag (named in §5.2 but never implemented until now) renders `string`, with an emitted encode-and-pin prologue.
4. **Primitive typedefs were opaque.** `ke_entity`, `ke_component_id`, and `ke_query_id` are `typedef`s of `uint64_t`/`uint32_t`; the extractor ignored `TypedefDecl` entirely, so they reached C# as undefined type names. The frontend now emits a `type_aliases` map (only for typedefs resolving to a primitive — one naming a struct or enum is a real type the description already carries), and every backend type mapping resolves through it.

**Two further generalizations this domain forced**:

- **A borrowing wrapper.** `EcsRegistry` never owned its `ke_ecs*` — `FlecsEcs` owns the handle and the registry reads through the pointer. Every provider now also gets `static X Borrow(ke_x* native)`, whose result's `Dispose` releases nothing. Deliberately a named factory rather than a constructor overload: `new X(ptr)` would be ambiguous against an idiom layer's own managed-typed constructor whenever a caller passes `null`, and `Borrow` states the ownership at the call site.
- **Type-name overrides.** `ke_ecs` derives to `Ecs`, which inside namespace `KernelEngine.Ecs` is unreferenceable without full qualification. `Convention.TypeNameOverrides` maps it back to `EcsRegistry`. Note the generated `INativeEcs` interface is deliberately *not* renamed with it — it exists to hand out the native pointer, so it is named after the native type, which is also the name every cross-domain consumer already knows it by.

### A.6 — `audio` (small, single-provider) — audited, migrated, cleared

`Audio.cs` deleted; `Generated/Audio.g.cs` + `Audio.Idiom.cs` (a `SoundHandle` wrapping the bare `uint` id) replace it.

**Fallibility was wrongly tied to a `bool` return.** `load_sound` returns `ke_audio_sound` (a value), not a boolean, but still takes the trailing `ke_error**` — a fallible call whose failure shows up in the out-param, not the return. `Convention.IsFallible` no longer requires a boolean return; a new `Convention.SignalsFailureByReturn` distinguishes the two shapes so `RenderSlotMethod`'s `Fallible` case can pick the right one: bool-returning slots still use `KernelError.ThrowIfFailed`; value-returning ones capture the result, check the out-param, and return the value.

**Two smaller fixes surfaced by the same domain**: a `ke_bool`-typed *parameter* (not just a return) rendered as C# `bool` without converting to a native byte at the call site; and a handle-based constructor didn't validate `handle.@ref == null`, so a caller passing an empty handle failed later at first use instead of immediately. Both fixed in the shared render path, so every previously migrated domain benefits too.

### A.7 — `physics` (`ke_physics_2d`, single provider + one enum + one struct) — audited, migrated, cleared

`Physics2D.cs` deleted; `Generated/Physics2D.g.cs` + `Physics2D.Idiom.cs` (`Vector2`-shaped overloads over the ABI's loose floats, `BodyHandle2D`/`BodyState2D` projections, and the "invalid handle is a silent no-op" policy) replace it. `BodyType2D` is no longer hand-written — generated from `ke_body_type_2d`.

**This domain forced three more `kabic` generalizations**:

1. **An `[out]` param with other input params in the same slot.** `get_body_state(body, out state)` reads as `State GetBodyState(body)`, not a pointer-taking void method — the classifier previously required the `[out]` param to be the *only* param before treating a slot as `ReturnsOutParam`. Relaxed to just require exactly one `[out]` param, keeping every other input in the signature.
2. **That relaxation regressed `ecs`'s `query_resolve`**, which also has exactly one non-sequence `[out]` param (`out_count`) alongside its sequence pair, and got misclassified as `ReturnsOutParam` instead of `Sequence`. Fixed by re-ordering the shape checks so `Sequence` is always evaluated first — a slot with both a pointer+count pair and a separate `[out]` is a sequence call whose count comes back as an out, never the other way around. Re-verified `ecs`'s generated output was unaffected by the reordering itself, only by the actual regression.
3. **A parameter typed directly as one of the description's own enums** (`ke_body_type_2d type`, no `[enum:]` tag needed) wasn't recognized — the backend only knew `[enum:]`-tagged primitive params. Added a check against `model.Enums` so a native-enum-typed parameter renders as the C# enum and casts back to the native type at the call site, same as the tagged case.

**Also found**: `Idioms.CsKeywords` covered only ~13 reserved words. `set_body_fixed_rotation`'s `fixed` parameter rendered as literal invalid C# (`bool fixed`) — the list was expanded to the full C# keyword set.

### A.8 — `text` (`ke_font_loader`, single provider, no factory) — audited, migrated, cleared

`FontLoader.cs`/`INativeFontLoader.cs` deleted; `Generated/FontLoader.g.cs` + `FontLoader.Idiom.cs` (the `Task.Run` async wrapper around the synchronous native decode, and copying the native atlas + glyph arrays into managed memory before `free_font` releases them) replace them. The struct types `ke_font_data`/`ke_glyph_metrics` were left to the existing ClangSharp-generated `Native/Generated/` bindings, same as every other domain — `kabic` only ever replaces the hand-written wrapper class, never the low-level struct/vtable layout bindings.

**A fourth `kabic` bug this domain's shape exposed**: `load_font` returns `ke_font_data *` — a pointer, not a boolean — while also taking a trailing `ke_error**`, so it hit the same value-returning-fallible path `audio`'s `load_sound` introduced (Appendix A.6). But a pointer-returning slot signals failure by returning NULL; the error out-param may or may not also be set (this ABI's own mock test left it unset on purpose), so checking `err != null` alone silently let a NULL result flow into the caller instead of throwing. `RenderSlotMethod`'s `Fallible` case now branches again on `CTypes.IsPointer(slot.Returns)`: a pointer-returning slot checks `result == null`; anything else keeps checking the error out-param as before. `KernelError.FromNative` already tolerates a null `ke_error*` (falls back to a generic message), so the pointer-null branch works even when the native failure path leaves the out-param unset.

### A.9 — `render` (`ke_render_service`, 42-slot vtable, cross-domain GPU vocabulary) — audited, migrated, cleared

The largest and most structurally different domain migrated to date. `WebgpuRenderModule.cs` never had a hand-written 1:1 wrapper class the way every other domain did — it's a composition root (device/module creation spanning window/ecs/runtime/scheduler/logger) that ALSO forwarded a curated ~13-slot subset of `ke_render_service` directly via raw `_core->slot(...)` calls, mixed into the same file. Migrating it meant generating the full 42-slot vtable as a real `RenderService` wrapper (nothing licenses generating only the slots one caller happens to use — the ABI doesn't know about callers) and then having `WebgpuRenderModule` compose it via `RenderService.Borrow(_core)`, replacing its manual marshaling with calls to the generated wrapper while keeping the composition-root logic (which has no ABI counterpart) as-is.

**Why this took a second, working attempt.** The first attempt stopped mid-session: `ke_render_service`'s params reference GPU handle types (`ke_gpu_buffer`, `ke_gpu_texture`, ...) and an enum (`ke_alpha_mode`) declared in headers this domain doesn't own (`gpu_device.h`, `gpu_enums.h`, `handles.h`) — and one of those, `ke_gpu_shader_stage`, wasn't even in the header initially checked; it's declared in a third header (`gpu_enums.h`) discovered only by grepping for it. Attempting to include those headers wholesale to resolve the missing types immediately re-created the problem this whole rewrite is meant to avoid: describing (and re-emitting, wrongly) a foreign domain's own vtables and enums.

**The fix: a new extraction mode, `--aux`.** A header can now be passed as `--aux <path>` instead of a primary target: its `TypedefDecl`s still populate `type_aliases` (so `ke_gpu_buffer` resolves to `ulong`, not an undefined name), but its `EnumDecl`/`RecordDecl`/`FunctionDecl`s are skipped entirely — its own vtables and enums are somebody else's domain to describe, and (as this domain's first attempt found empirically) parsing them here was measurably less stable than parsing them as a real target: an earlier attempt at working around the same problem with a generation-time `--only <name>` allowlist (rendering everything but only emitting the wanted names) left the foreign structs/enums fully parsed and in the model, and re-running extraction against the exact same header set with the exact same flags produced two DIFFERENT `ke_api.json` files across runs — a real function-pointer's param names sometimes came back correct, sometimes `null`, and one enum's value flipped from an integer to a string. `--aux` fixed the instability as a side effect of fixing the actual design problem: not parsing what isn't needed removes the flaky code path entirely rather than working around its output.

**A latent bug found on the way there, general-purpose**: the extractor keys its `sourceBytes` dictionary (used for every byte-offset slice — param names, enum literals) by clang's own reported `loc.file` string, compared against the command-line header path with no normalization. Depending on how `-I` paths and header args were spelled (relative vs. absolute vs. through this environment's own bind-mount prefix), the two representations of "the same file" sometimes didn't match — silently falling back to the WRONG file's bytes (`sourceBytes.Values.First()`) rather than erroring, which is what produced the run-to-run instability above. Both sides are now normalized through `Path.GetFullPath` before the lookup. This alone didn't fully explain the instability (the bind-mount prefix isn't something `GetFullPath` can reconcile — it's not a symlink, it's two genuinely different absolute paths naming the same inode), which is what made `--aux` the real fix rather than a nice-to-have on top of a normalization patch.

**A second real bug, unrelated to extraction**: ClangSharp maps the C ABI's own `ke_bool` typedef to a raw `byte` delegate return — unlike the literal `bool`/`_Bool` keywords, which it maps to C# `bool` directly. `begin_frame`/`end_frame` (`Fallible`, byReturn) and `try_get_mesh`/`try_get_texture`/`try_get_material` (`Try`) both return `ke_bool` and failed to compile (`byte` doesn't implicitly convert to `bool`). Fixed in two places: `Convention.BooleanReturnTypes` now includes `"ke_bool"` (so `SignalsFailureByReturn` recognizes it), and both the `Fallible` byReturn and `Try` render paths append `!= 0` to the native call when `slot.Returns == "ke_bool"` — the same conversion the pre-existing `Plain` shape already had for exactly this reason, just missing from these two newer shapes. No previously migrated domain's `Fallible`/`Try` slot happened to be spelled `ke_bool` (only literal `bool`), so this went unnoticed until render's `begin_frame`.

**A third, purely cosmetic bug fixed along the way**: a slot already named `try_get_mesh` (Pascal-cased: `TryGetMesh`) rendered as `TryTryGetMesh` — the `Try` shape unconditionally prepended `Try`. Now checks whether the name already starts with `Try` first.

**Scope note**: only `ke_render_service` was migrated — `ke_gpu_device` (the L4 GPU ABI `gpu_device.h` itself declares, ~30 more slots) is untouched; nothing in C# calls it directly today (Zig-side render passes do), so there's no consumer forcing a decision on its own tag annotation yet. `asset_resolver.h` (deferred earlier this branch specifically because it depends on `ke_render_service`) is now unblocked and can proceed.

### A.10 — `asset_loader` / `image_loader` (two single-provider domains) — audited, migrated, cleared

Both domains share `mesh_data.h`'s plain structs (`ke_model_data`, `ke_texture_data`, ...) — never generated by `kabic` (it only ever replaces a hand-written wrapper class, not the ClangSharp-generated struct/layout bindings, per every prior domain) — so migrating them meant only the two vtables.

`image_loader` (`ke_image_loader`, 2 slots: `load_image`/`free_image`) is the same shape as `text`'s `ke_font_loader`, right down to the pointer-returning-fallible `load_image`. `ImageLoader.cs` had its mechanical half deleted; `Generated/ImageLoader.g.cs` + `ImageLoader.Idiom.cs` (the `IImageData` deferred-copy view and the `Task.Run` async wrapper) replace it. `ImageData` (the owning view class) was untouched — it isn't the domain's provider, just a private nested concern of the wrapper.

`asset_loader` (`ke_asset_loader`) introduced the first real `[raw_callback]` case since `scheduler`'s `dispatch` family (Appendix A.4): `load_model_async` takes `ke_scheduler *` (a cross-domain pointer, fine — passed through untouched, same as any other pointer param) and `ke_load_model_complete_func` (a bare C function pointer, no `[callback]` vtable-by-value shape to hang a trampoline off of). Tagging its parameter `[raw_callback]` drops the whole slot from generation, exactly as it does for `scheduler`'s dispatch slots — the managed async surface (`Task<IModel>`, `GCHandle`, `[UnmanagedCallersOnly]`) has no ABI-derivable answer, so it stays fully hand-written in `AssetLoader.Idiom.cs`, unchanged from the pre-migration code except for reading the native pointer through the generated `INativeAssetLoader.Native` instead of a private field.

**Both wrapper classes live in a different project than their own native bindings** — `AssetLoader`/`ImageLoader` are in the backend plugin projects (`KernelEngine.Asset.Assimp`, `KernelEngine.Asset.StbImage`), while `ke_asset_loader`/`ke_image_loader`'s ClangSharp struct bindings live in the base `KernelEngine.Asset` project. This is the same split `render`'s attempt at `image_loader` alone first flagged as a structural mismatch (Appendix A.9's predecessor note, now resolved): nothing in `kabic`'s generation actually requires `--namespace` and `--native-namespace` to share a common root — the generated class just needs a `using` for whichever namespace its native types live in, which `KernelEngine.Asset.Native` being `global using`d in both plugin projects already provides. No kabic change was needed; the earlier hesitation was unfounded.

### A.11 — `asset_resolver` (`ke_asset_resolver`, 10 slots, cross-domain data + a backend-agnostic boundary) — audited, migrated, cleared

The last unmigrated piece of the `asset` domain — deferred earlier in the branch specifically because it depends on `ke_render_service`, unblocked by Appendix A.9. `NativeAssetResolver.cs` had its mechanical half (constructor's factory call, the ten resolve/free slots) split into `Generated/NativeAssetResolver.g.cs` + `NativeAssetResolver.Idiom.cs`; the four owning view classes (`ResolvedTextureData`, `ResolvedMeshData`, `ResolvedFontData`, `MaterialSpec`) were untouched, same as `image_loader`'s `ImageData`.

**A genuine kabic bug, not just a new shape**: `resolve_texture`/`resolve_font` are the first `ReturnsOutParam` slots with a `[utf8]` string param in the same signature — every prior domain's `ReturnsOutParam` slots (`physics`'s `get_body_state`, `render`'s upload/create methods use a different shape) never combined the two. `RenderSlotMethod`'s `ReturnsOutParam` case never called `Utf8Prologue` at all: the generated method referenced a `pathPtr` variable that was never declared, a straight compile error. Fixed by adding the same `Utf8Prologue`/depth-tracked-brace pattern every other shape already had. `TupleOutParams` doesn't take any non-out params today (`window`'s `get_size` is the only user), so it wasn't hit by the same gap, but it's the same latent gap if a future slot combines the two shapes — noted, not yet fixed, since nothing exercises it.

**A second, more consequential bug in `CTypes.Deref`, general-purpose**: `resolve_texture`'s `out` param is `ke_texture_data **` — a pointer-to-pointer (the resolver allocates a `ke_texture_data` elsewhere and hands back a pointer to it), unlike every prior `[out]` param in every migrated domain, which was always a single pointer to caller-provided storage (`ke_mesh_handle *out`, `int32_t *width`, ...). `Deref` used `TrimEnd('*', ' ')`, which strips *every* trailing `*` at once — collapsing `"ke_texture_data **"` straight to `"ke_texture_data"` (a value type) instead of `"ke_texture_data *"` (one level down). `ResolveTexture` generated as returning `ke_texture_data` by value with no way to populate it correctly. Fixed to strip exactly one trailing `*` per call, matching what every call site actually expects (they already recurse or call it in a loop when they need more than one level off). No other migrated domain had a `T**` out-param, so this went unnoticed until now.

**A new tag, `[opaque]`, for a boundary kabic can't derive from the ABI alone**: `resolve_texture_into`/`resolve_mesh_into`/`resolve_material_into` take `ke_render_service *core` — but `KernelEngine.Framework` (where this wrapper lives) deliberately never references a concrete render backend project (`KernelEngine.Render.Webgpu`), so it can't name that struct. Tellingly, `ke_asset_resolver`'s own ClangSharp-generated bindings already collapse this exact parameter to `void*` in the native delegate field, for the same reason (whatever project generated *those* bindings never had `render_service.h` in view either). `[opaque]` on the parameter's doc comment renders it as `void*` regardless of its real C type — matching the pre-existing ClangSharp behavior for a type this consumer can't (and shouldn't) resolve, rather than kabic's fuller AST view papering over a genuine project-boundary constraint with a type nothing here can compile against.

**Naming**: `ke_asset_resolver` derives to `AssetResolver`, but the pre-migration public name was `NativeAssetResolver` (nothing else in this branch collides with `AssetResolver` — the rename would have been harmless) — added to `Convention.TypeNameOverrides` purely to avoid an unforced rename of a type with zero other call sites today, not for any structural reason like `EcsRegistry`'s.

This closes out the `asset` domain (`asset_loader`, `image_loader`, `asset_resolver`) and, with `render`, both branches that were blocked earlier in the migration arc.

### A.12 — `framework` (`world`, `scene_tree`, `scene_loader`, `input_actions`) — audited, migrated, cleared

Four small vtables in `src/zig/framework/include/kernel_engine/framework/` (the framework plugin itself moved to Zig; only its C-ABI contract headers matter here). All four share one shape this branch hadn't hit yet: a hand-written wrapper property/method whose NAME already matches what `kabic` would derive for the RAW vtable getter, with a DIFFERENT return type — `World.Ecs`/`.Runtime`/`.SceneTree` (managed types, DI-injected or lazily wrapped) vs. the raw `ke_ecs*`/`ke_runtime*`/`ke_scene_tree*` the vtable slots return; `SceneTree.Root` (a plain `ulong` property) vs. a generated `Root()` method of the same name. C# does not allow a property and a method with the same name in one type, so generating these unconditionally would not compile.

**A new tag, `[idiom]`**: marks a slot whose managed surface is entirely superseded by an existing, differently-shaped hand-written member of the same name — skipped from generation like `[sink]`/`[lifecycle]`/`[raw_callback]`, but for a different reason (a naming collision with intentional hand-written API, not "no ABI-derivable shape"). Applied to `world.ecs`/`.runtime`/`.scene_tree` and `scene_tree.root`. `scene_loader.load` also got it, but for the `[raw_callback]`-adjacent reason `asset_loader`'s `load_model_async` established: `Load` rethrows a managed exception the script-factory trampoline caught mid-call, which has no ABI-derivable shape either.

**`[raw_callback]` on a slot's own RETURN type, not just a param — a real kabic bug**: `world.get_component_apply` returns `ke_component_apply_fn`, a bare C function pointer, with no param carrying the tag at all (the tag was on the doc summary, correctly parsed into the slot's own tags — but `RenderProvider`'s skip check only ever inspected `cs.PublicParams.Any(p => p.Has("raw_callback"))`, never `cs.Slot.Has("raw_callback")`). The generated method referenced the bare type name `ke_component_apply_fn`, which has no top-level C# binding (ClangSharp only ever emitted it inline as a delegate's own generic parameter, never as a named type) — a compile error. Fixed by checking the slot's own tag too.

**A partial-method hook for idiom-owned Dispose logic, needed for the first time**: `World` (owns a scene-tree handle from a DIFFERENT domain's factory plus a list of `GCHandle`s pinning registered component-apply callbacks) and `SceneLoader`/`NativeInputActions` (each owns a `GCHandle` for a registered callback) all need extra cleanup beyond releasing their own native pointer — but the generated `Dispose()` is a complete method, and the idiom layer can't also declare a `Dispose()` in the same partial class (duplicate member). Every generated `Dispose()` now calls `partial void OnDispose();` first; a C# partial method with no implementation compiles to nothing, so every domain migrated before this one is unaffected (still verified byte-identical except for this one addition) and only the three with real idiom cleanup implement it.

**`TupleOutParams` never included non-out params — a real, previously-flagged gap that finally got exercised**: `get_axis2d`/`get_axis3d` take `action_id` alongside their float-triple out-params — until now every `TupleOutParams` user (`window.get_size`) took ONLY out-params, so `Classifier`'s `tupleOut` condition required `allOut.Count == ps.Count` (nothing else allowed) and the C# backend's tuple-returning method signature was hardcoded to zero parameters. Both relaxed the same way `ReturnsOutParam` already was for `physics` (Appendix A.7): the classification only requires two-or-more `[out]` params, and the render path threads any other public param through as an ordinary input (with its own `Utf8Prologue` support, matching `ReturnsOutParam`'s A.11 fix). Re-verified byte-identical for `window.GetSize` (the only pre-existing `TupleOutParams` user) after the change.

**Naming**: `ke_input_actions` derives to `InputActions` (no collision), but the pre-migration name was `NativeInputActions` — same unforced-rename-avoidance override as `NativeAssetResolver`. `AddAction`'s `type` parameter is now the Pascal-cased `ActionType` enum (this domain's OWN enum, so — unlike `ke_alpha_mode`'s cross-domain `[opaque]`-adjacent case — the rename is correct, not a mismatch) instead of the raw `ke_action_type`; and the generated `GetAxis2d`/`GetAxis3d` tuples are named `(OutX, OutY)`/`(OutX, OutY, OutZ)` (Pascal-cased from the ABI's own `out_x`/`out_y`/`out_z` param names) rather than the pre-migration `(X, Y)`/`(X, Y, Z)` — a cosmetic difference with zero call sites depending on the old names today.

**A drift-checker gap, found while wiring the manifest**: these four domains all generate into the same physical `KernelEngine.Framework/Generated/` directory (unlike every prior domain, one project each) — `check_api_drift.cs`'s directory comparison required the temp-regenerated set and the committed set to match EXACTLY, so any domain's own regeneration correctly flagged every SIBLING domain's files as unexpected "drift". Fixed to check only that a domain's own regenerated files are present and byte-identical in the committed directory, not that the directory contains nothing else — the correct semantics once a directory can legitimately hold more than one domain's output.
