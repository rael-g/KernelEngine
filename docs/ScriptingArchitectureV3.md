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

Verified end to end on `ke_input` (§8.3) and the `ke_logger`/`ke_logger_sink` callback shape (compile-probed). Not yet done: the tag vocabulary will grow as harder domains surface needs it doesn't cover (§8.4) — Stage 0's infrastructure is stable, its tag *vocabulary* is deliberately open-ended per §8.7.

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

### 8.5 Stage 3 — acceptance test: a second language

Implement a Lua or Python `kabic` backend plus a runtime shim, consuming the same `ke_api.json`. For a dynamic language this should require **no build-time codegen at all** (§6.2).

**Pass condition**: no native change, no hand-written per-domain wrapper. If either is needed, the strategy has a gap and the gap is now visible with a concrete failing case.

### 8.6 Stage 4 — `ke_node_host` (Track 4)

Last, and only now, because it registers into an ABI that Stages 1–2 are still reshaping. Design in `ScriptingArchitectureV2.md` §4/§5.

### 8.7 Invariants held throughout

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

---

## 12. Summary

| Track | Fixes | Baseline it removes | Priority |
|---|---|---|---|
| 1 — Completeness | Engine capability above the ABI | ~900 (Toolkit services) + unblocks every other language | **Blocking prerequisite**, per domain (§4) |
| 2 — Describability | Headers carry syntax, not semantics | Enables all of Track 3; moves 1 793 doc lines to the ABI | After 1, per domain |
| 3 — Derivation | Wrappers written by hand | ~3 600 of the 5 195 | After 2, per domain |
| 3a — shared classification | Each backend re-deriving slot semantics, and diverging | — | Once (§6.1) |
| 3b — per-language backend | Seven rendering decisions + shim | — | Once per language (§6.2) |
| 4 — Node ergonomics | Registration mechanics per language | ~600 | Last (§8.6) |

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
