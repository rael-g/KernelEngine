# Kernel Architecture V2 — What Is Allowed to Live in the Kernel

**Status**: Doctrine accepted. Domain ejection complete (2026-06-15, branch `feat/kernel-v2`): all domain headers ejected from `src/c/kernel/include/` to `src/c/<domain>/include/`. Render components + `material_file` moved to `render/` domain. Next: §7.3 vtable audit.

**Audience**: Engine maintainer + plugin/domain authors (render / physics / audio / input / text / asset / scripting).

**Companion docs**: [`RuntimeArchitectureV2.md`](RuntimeArchitectureV2.md) (*how systems run*), [`RenderArchitectureV2.md`](RenderArchitectureV2.md) (*how the renderer works*). This doc is the constitution the other two inherit: it defines *what has the right to exist inside the kernel at all, and why*.

**Supersedes**: Kanban cards **K1**, **K3**, **A12**, and Bug **1.37 / B5.1** — those are the seeds of this doctrine in card form. Once this doc is accepted they become execution items *of* this doc, not independent decisions.

---

## 1. Purpose — the thesis

The engine doctrine has always been *"kernel = building blocks, never built blocks."* In practice the kernel grew **header squatting**: it *declares* contracts it never *uses*. A `grep` proves it — the kernel's own implementation (`src/c/kernel/src/`) includes **zero** domain contracts. It only ever touches `common`, `context`, `logger`, `ecs`, `resource_cache`, `input`, `engine`. Yet `include/` carries `render/`, `audio/`, `physics/`, `window/`, `text/`, `asset/` — contracts no kernel code consumes.

The separation we want **already exists physically**. What's missing is the *doctrine* that says these domains don't belong to the kernel, and the discipline that keeps the minimization safe instead of merely relocated.

The driving principle:

> **The more the kernel ignores, the more resilient it is.** A kernel that knows render must be extended when render changes. A kernel that knows nothing of render survives every renderer it will ever host — including *no renderer at all* (headless). We did this with render passes and GPU extensions; we now do it with the domains themselves. *"If we can't embrace the whole world, we embrace no one."* The kernel embraces only the execution model. It embraces no domain.

The endpoint: `src/c/kernel/` compresses to **runtime + scheduler contract + ECS + a few foundation primitives**. Render, audio, physics, input, text, asset, framework become **independent domains** — `src/c/render/`, `src/c/audio/`, … — each with its own contract, its own implementations, its own C# binding, and its own version. The kernel does not know they exist.

---

## 2. The decision criterion — not "universal", but "does the kernel execute against it?"

"Is X universal?" is the wrong test — it leads to unwinnable debates ("is 3D audio universal?"). The right test is mechanical. Every header falls into exactly one of three tiers:

| Tier | Test | Contents |
|---|---|---|
| **1 — Kernel (execution substrate)** | *Does the scheduler or the ECS need this to run a system?* | ECS, runtime/scheduler contract, `system_ctx` |
| **2 — Foundation (domain-agnostic primitives)** | *Is it a generic utility anyone uses, imposing no domain?* | allocator, logger, `common/` (containers, math, hash, handles, error), `resource_cache`, `task_scheduler`, shared **data contracts** |
| **3 — Domains (independent)** | *Everything that passed neither of the above.* | render, audio, physics, input, window, text/ui, asset, framework |

Tier 2 stays physically inside `src/c/kernel/` **for now** — splitting it into seven micro-libraries trades a fat kernel for a CMake nightmare. The doctrine is about *what may enter the kernel*, not about maximal fragmentation. Eject domains first; reconsider a separate `foundation` target only if it earns its keep.

---

## 3. The coupling doctrine — two kinds of contract

Radical minimization is only safe if domains stop *depending on each other's APIs*. Otherwise you replace an explicit kernel contract with an **implicit** one (shared assumptions with no owner) — strictly worse, because nobody reviews or versions it. The rule that prevents that:

> **Domains never call each other through APIs. They couple through data — components on the ECS bus.**

This forces a distinction the codebase has not made explicit before. There are **two kinds of contract**, with opposite rules:

### 3.1 Behavior contracts (vtables) — per-domain, never cross-domain

`ke_render`, `ke_audio`, `ke_physics`. A struct of function pointers. Its *only* purpose is **backend interchangeability within a domain** (bgfx ↔ a future WebGPU renderer). It is **never** the channel between two domains. Render's vtable is called by render's own systems, never by physics.

This is where *"throw the API away rather than Frankenstein it"* lives: because a behavior contract's lifecycle is decoupled from the kernel's, an aged contract is replaced by publishing `render/v2` — the kernel ABI never moves.

### 3.2 Data contracts (component layouts) — shared, the real coupling surface

`transform`, `hierarchy`, `name`. Pure POD. No functions, no vtable, no DLL. **This** is the inter-domain coupling channel — the "data bus" made concrete. Physics writes `transform`; render reads `transform` + a world-matrix; neither knows the other exists.

A data contract imposes nothing *behavioral* — it's an agreement on bytes. That is why it does not violate "no imposed API": a struct layout is not an API in the impose-a-vtable sense, and a domain that doesn't care (headless) simply never includes it. The reusability you want (*"nobody invents from scratch"*) lives here, without imposition.

**The litmus that resolves "where does X belong":** is X *behavior* (has a backend to swap)? → behavior contract, owned by its domain, outside the kernel. Is X *data* (a layout domains agree on)? → data contract, foundation tier, owned by no domain.

---

## 4. The tiers, concretely

### 4.1 Tier 1 — Kernel

- **ECS** (`ke_ecs` contract — storage/query). Storage impl is the flecs plugin; the kernel holds only the contract.
- **Runtime / scheduler** (`ke_runtime`, `system_ctx`). Impl is `src/c/runtime/`. The kernel holds the contract; `system_ctx` is the only doorway to component memory (R2.5c safety doctrine).
- Nothing domain-specific. **No spatial concept** — see §6.

### 4.2 Tier 2 — Foundation

- `allocator`, `logger`, `common/`, `resource_cache`, `task_scheduler` — generic, no domain opinion.
- **Shared data contracts** (§3.2): `spatial` (transform, future aabb/bounds). POD headers, no impl.
- `resource_cache` is already correctly type-erased — it keys `void*` by path with a refcount and a destructor callback. It does **not** know what a "texture" is, and must never learn. *Resource kinds* are owned by whoever owns them; loaders (assimp, stb_image) are domain plugins; the cache is a generic primitive, like a hash map.

### 4.3 Tier 3 — Domains

Each domain is self-contained:

- **One behavior contract** (vtable), header-only, static-linked. *(APIs are not DLLs; only implementations are.)*
- **One or more implementations** (the DLLs): bgfx renderer, miniaudio, Box2D, GLFW window, …
- **Its own C# binding project** — one per domain, generated via `scripts/generate_bindings.py`. One contract → one `.rsp` → one binding csproj.
- **Its own components, systems, services, modules** — a domain ships everything it needs. Render ships `camera`/`light`/`mesh` components + the render systems that read them; physics ships its bodies + the physics systems; UI ships `canvas`/`label`/`font`. There is **no central component grab-bag**.
- Domains couple to each other **only** through Tier-2 data contracts (§3).

---

## 5. Phases are opaque ordered labels — the headless acid test

**Decision (fork #1 = b):** the scheduler must **not** bake domain names (`KE_PHASE_RENDER`, …) into a kernel enum. A baked enum means "the kernel knows render exists." Instead, phases are **opaque ordered labels**; `"render"` is a convention modules agree on, not a kernel identity.

**Acid test:** the engine must run **headless** — zero render systems registered, no renderer linked — and the kernel must not notice. If removing the render domain requires touching the kernel, the boundary is wrong. (Cross-check the current phase enum in [`RuntimeArchitectureV2.md`](RuntimeArchitectureV2.md) §3 against this; the phase scheme is a candidate to become legacy.)

A render system is, to the scheduler, just `void system(ke_system_ctx*)` running in some phase. It happens to call the `ke_render` vtable — but the scheduler sees nothing about pixels. The mechanism for "kernel doesn't know render" is therefore **already present**; this section only forbids re-leaking a domain name back into the phase identity.

---

## 6. Spatial vs scene-graph — where `transform`, `hierarchy`, `name` live

A `grep` (ignoring compiled `bin/`/`obj/`) shows only **framework** and the managed wrapper/binding layer read `hierarchy`/`name`. **No native render/physics/audio code traverses hierarchy** — render reads a world-matrix; physics reads/writes position.

- **`hierarchy`, `name` → framework.** Pure scene-graph; only framework cares.
- **`transform` → its own `spatial` data contract (Tier 2).** It is the *one* genuinely cross-domain layout (render reads, physics writes). It cannot live in:
  - the **kernel** — that would give the kernel a spatial concept, breaking §4.1 (a headless data-sim has no notion of 3D space);
  - the **framework** — render would then depend on framework, but framework is the *composition* layer and depends on render. **Cycle.**

  So `transform` gets a minimal standalone data contract — named **`spatial`** to hold transform now and `aabb`/`bounds` later, separate from scene-graph PODs. Resulting DAG, acyclic: `spatial → {}`, `render → spatial`, `physics → spatial`, `framework → spatial`.

Transform **propagation** (local → world) is *behavior*, not part of the contract — it's a system someone registers (framework or a small scene-systems module), reading/writing the `spatial` data contract.

**Framework is a domain too.** It shrinks like the kernel: it owns only the irreducible scene-graph (`hierarchy`/`name`) and the composition glue. `Node` is already moving to Toolkit (it's an abstraction, never a native concept). `camera`/`light`/`mesh` leave for the render domain; `canvas`/`label`/`font` are the UI/text domain. Framework knows the most primitive things and nothing else.

---

## 7. Encapsulation doctrine — inject at construction, never expose as a property

A12 has two halves that are **the same disease at two layers**:

- **C layer (A12.2):** vtable structs expose de-facto private state (`allocator`, `logger`) as **public fields**, because vtables were modeled as classes. If `ke_logger` were a class, the allocator would be a *private* field, not a public property.
- **C# layer:** `public ke_X* Native` is a "getter" returning a **mutable pointer** — not encapsulation, a public field in disguise. It enables the train-wreck `world.Allocator.Something()` we want banned.

The unifying rule:

> **Inject at construction; never expose as a property.** A dependency (allocator, logger, …) is a *factory parameter*, stored as private/opaque state. There is no `get`. You cannot read it back, cannot reach through it. In C → opaque state behind `void*`. In C# → private field; the wrapper exposes **operations, not the sub-object.**

This kills all three symptoms at once: the vtable-privacy offense (A12.2), the "getter returns a manipulable pointer" weirdness, and Law-of-Demeter train-wrecks (`world.Allocator` simply does not exist, so it cannot be chained).

Two corollaries that the rule above *implies* but must be stated outright, because they're the part most easily violated:

**(a) The vtable carries consumer operations — and nothing else.** A vtable struct is the surface the *consumer* calls. Dependencies, internal state, scratch buffers, back-pointers — none of those belong on it. They live in the impl's private state struct (behind `void*`), populated by `create`. The test for any field on a vtable: *does a consumer call this?* No → it is not a vtable member; it's private state. The allocator pointer sitting on `ke_*` vtables today is the canonical violation, but the audit (A12.2) sweeps for **all** of them, not just allocator.

**(b) Dependencies are declared in `create`, by need — never mandated by doctrine.** No dependency is obligatory. The factory signature of an implementation declares *exactly* the dependencies that implementation actually consumes:

- An impl that allocates declares `ke_allocator*` in its `create`. One that doesn't, takes none.
- An impl that logs declares `ke_logger*` in its `create`. One that's silent, takes none.

There is no "every component must accept an allocator" rule, and no implicit global to fall back on. The `create` signature **is** the honest, complete statement of what that implementation needs — read it and you know its dependencies, no more, no less. This is the opposite of the historical habit of threading an `ke_allocator*` through everything "because that's the pattern" (the cargo-culting A12.1 names).

### 7.1 The cross-binding handle problem — and the honest ceiling

The hard case: binding A's factory needs binding B's native handle (creating a renderer needs the allocator pointer for `ke_render_bgfx_create(allocator_ptr, …)`). Today that's why `Native` is public — and the project banned `InternalsVisibleTo`, so a public pointer felt like the only door.

**The honest limit (stated plainly, not maquiado):** *full physical enforcement across separate assemblies, without `InternalsVisibleTo`, is impossible in C#.* The CLR offers exactly three cross-assembly visibilities: `public`, or `internal` + IVT. IVT is banned. If a pointer must cross the assembly boundary at runtime (and it must, for the native create), it has to be `public` at that point. There is no third door. Anyone promising "physically impossible to leak" is lying.

**What *is* achievable — and is a real upgrade over today's public `.Native`:**

1. **No handle property on the friendly wrapper.** `Allocator` has no `.Native` getter. `world.Allocator.Something()` *does not compile* — the property to chain doesn't exist. Demeter is killed physically.
2. **The handle crosses only through a segregated, deliberately-ugly interface** — e.g. `public interface INativeHandle { nint Handle { get; } }` in the bindings layer. A factory takes `INativeHandle` (or `INativeAllocator`), never `Allocator`. Grabbing the pointer requires a deliberate cast to that interface — explicit, greppable, reviewable in a PR. It is no longer a loose `.Native` anyone picks up by accident.
3. **Vertical containment stays free via the reference graph:** Toolkit and game code do not reference the bindings, so they *physically cannot see* `INativeHandle`. *This* is real physical enforcement — at the toolkit boundary, not the wrapper boundary.
4. **The wrapper keeps ownership of lifetime** — the interface hands out only the pointer the native create needs to read; you cannot dispose/realloc through it.

The ceiling, stated honestly: we move from *"public, anyone takes it, contained only by convention"* to *"impossible by accident or by train-wreck; deliberate and auditable when intentional; contained vertically by the assembly graph."* That resolves the factory case (render asks for `INativeAllocator`, never fishes `allocator.Native`) and is the maximum reachable without IVT.

### 7.2 Allocator doctrine (A12.1)

Separate from the privacy fix, the open doctrine question: *does everyone actually need an injected allocator, or are we cargo-culting?* The answer, given corollary (b) above: **allocator injection is opt-in by need, not a blanket mandate.**

- Third-party libs (bgfx, GLFW, Box2D, assimp, stb, flecs) bypass our allocator entirely — so "centralized memory control" is **already partly a fiction**; we monitor *our* allocations, not theirs. Be honest about that leakage rather than pretending otherwise.
- Target rule: **an implementation that allocates declares `ke_allocator*` in its `create`; one that doesn't, declares none.** No layer (kernel, foundation, or plugin) is forced to thread an allocator it doesn't use, and there is no implicit global to fall back on. Where allocation strategy matters, the impl picks it (GC / arena / frame / malloc) — and the choice is visible in the `create` signature, not hidden behind a doctrine that pretends every component is allocator-aware. Encourage arena/frame allocation where it measurably matters (render frame data, ECS scratch, command queues) and verify which subsystems already do; third-party leakage is documented, not hidden.

### 7.3 The full vtable audit

The corollaries above don't apply themselves. Every `ke_*` vtable in the codebase predates this doctrine and was written under the "vtable = class" mental model, so the offenses are spread everywhere, not concentrated in one struct. This warrants a **complete, exhaustive sweep of every vtable the engine declares** — not a spot-fix of the allocator field.

**Scope:** every `typedef struct ke_*` that holds function pointers — across the kernel *and* every domain (render, window, audio, physics, input, text, asset, framework, runtime, ecs, task_scheduler, resource_cache, logger). Enumerate them first (`grep` the public headers for vtable shapes); the list is the audit's checklist.

**For each vtable, classify every member against corollary (a)'s test — *does a consumer call this?*:**

- **Function pointer the consumer invokes** → legitimate vtable member. Keep.
- **Dependency** (allocator, logger, another vtable, a back-pointer to the owner) → **move to the impl's private state struct (`void*`), populate it in `create`.** Remove from the vtable.
- **De-facto private state** (handles, caches, scratch, counters, flags the impl mutates) → same: opaque state behind `void*`. Remove from the vtable.
- **Read-only datum the consumer genuinely needs** (rare) → expose via a *getter function pointer* that returns a value/copy, never as a raw mutable field.

**Output:** a per-vtable verdict table (member → classify → action), and the refactor that lands it. The allocator pointer is the canonical offender and the worst (it pairs with the A12.1 doctrine), but the audit's value is catching the *others* — the ones nobody has noticed yet precisely because "it's just a field on the struct" reads as normal. Pairs naturally with the domain ejection (§9): a vtable is cleaned as its domain leaves the kernel, so the audit rides along with the migration rather than being a separate stop-the-world pass.

---

## 8. Versioning — per-domain, independent lifecycles (fork #3)

Once each domain owns its ABI, the kernel version stops being the single anchor — and that's the point.

- **Each domain versions itself.** Domains do not synchronize unless one depends on another (and by §3 they shouldn't — they couple through data contracts, not each other's APIs).
- **Implementations follow semver** (a renderer impl can patch/minor/major freely).
- **Behavior contracts (the vtables) bump major only** — a contract change is, by definition, a breaking change; there is no "minor" tweak to an ABI shape.
- **Composition is asserted, not assumed.** The framework (composition layer) is responsible for asserting that the set of domain versions it wires together is compatible. *(Open: an explicit "platform manifest" pinning a known-good set vs. per-domain semver checks at wire time — decide during implementation.)*

---

## 9. Migration map — header by header

Direction, not a mechanical checklist. Domain contract headers move out of `kernel/include/` into their own domain home following the existing plugin include convention (`src/c/<domain>/include/kernel_engine/<domain>/…`); implementations already live in `src/cpp/<domain>/…` / `src/c/<domain>/…`. **Search the existing plugin layout before moving each one** (project rule #3).

| Current header(s) | Tier | Action |
|---|---|---|
| `ecs/*`, `runtime/runtime.h`, `runtime/system_ctx.h` | 1 | **Stay** (kernel execution substrate) |
| `context/{allocator,types}.h`, `logger/*`, `common/*`, `resource_cache/*`, `task_scheduler/*` | 2 | **Stay** (foundation; revisit a separate target only if earned) |
| `framework/components.h` → `transform` | 2 | **Extract** to new `spatial` data contract |
| `framework/components.h` → `hierarchy`, `name` | 3 | **Keep in framework** (only framework reads them) |
| `framework/components.h` → `camera`, `directional/point/spot_light`, `mesh` | 3 | **Move to render domain** (render owns its components) |
| `framework/material_file.h` (`ke_material_spec`) | 3 | **Move to render/asset domain** (`.material` is a render-asset schema) |
| `framework/{world,scene_tree,scene_loader,input_actions}.h` | 3 | **Framework domain** (composition layer; slim it) |
| `render/*` (light, material, mesh, render, render_graph, shader_compiler, texture) | 3 | **Eject** → render domain |
| `audio/audio.h` | 3 | **Eject** → audio domain |
| `physics/physics_2d.h` | 3 | **Eject** → physics domain |
| `window/window.h` | 3 | **Eject** → window domain |
| `text/font.h` | 3 | **Eject** → text/ui domain |
| `asset/*` (asset_loader, asset_resolver, image_loader, mesh_data, mesh_shape) | 3 | **Eject** → asset domain |
| `input/*` (event, input, key, snapshot) + `src/input/` impl | 3 | **Eject** → input domain. The impl must leave the kernel too (fork #4: input is a domain) |
| `engine/frame_packet.h` + `src/engine/frame_packet.c` | — | **Legacy, keep until render v2.** Still load-bearing for the v1 render path (`src/cpp/render/core/`). **But its leak into `ecs/system.h` must be cut first** — a render-bridge concept has no business in the `ke_system` contract (§9.1) |
| `engine/frame.h`, `threading/frame_sync.h` | — | **Audit with `frame_packet`** — same render-pipelining lineage; classify when render v2 lands |

### 9.1 The `frame_packet` tentacle — first untangling, independent of everything else

`frame_packet` is not dead weight; it has tentacles in the **execution substrate**: it's `#include`d by [`ecs/system.h`](../src/c/kernel/include/kernel_engine/kernel/ecs/system.h), [`framework/components.h`](../src/c/kernel/include/kernel_engine/kernel/framework/components.h), and [`threading/frame_sync.h`](../src/c/kernel/include/kernel_engine/kernel/threading/frame_sync.h), on top of the legacy render core. This is the canonical example of the Frankensteinization this doc exists to stop — a render concept fused into `ke_system`.

It stays alive while render v1 lives. But **`ecs/system.h` must stop mentioning `frame_packet` now** — that decoupling does not depend on render v2 and is the first concrete cleanup.

---

## 10. Non-goals & explicit limits

- **Not a big-bang rewrite.** Domains eject one at a time; the engine keeps building between each. A domain's removal should degrade the engine *cleanly* (no renderer = headless, not "refuses to boot").
- **Not maximal fragmentation.** Tier 2 stays in the kernel until a split earns its keep. Seven micro-libs is a cost, not a virtue.
- **Not "leak-proof C# handles."** §7.1 — the reachable ceiling is "no accidental / no train-wreck / explicit-and-auditable when deliberate," not cryptographic impossibility. Don't claim more.
- **`frame_packet` is not deleted here.** It's tagged legacy and dies with the v1 renderer; only its substrate leak is cut now.

---

## 11. Open questions

1. **Composition versioning** (§8): explicit platform manifest vs. per-domain semver asserted at wire time.
2. **Phase model** (§5): confirm against [`RuntimeArchitectureV2.md`](RuntimeArchitectureV2.md) §3 whether the current phase enum becomes legacy outright or degrades to opaque labels in place.
3. **`spatial` membership** (§6): transform now; do `aabb`/`bounds`/`world_matrix` join it, or split further when render v2 defines its culling inputs?
4. **Foundation target** (§2): if/when Tier 2 earns a physical split out of `src/c/kernel/`.

---

## 12. Status & next actions

- **Doctrine accepted** (this conversation). Forks resolved: #1 = opaque phases; #2 = static contracts + per-domain bindings; #3 = per-domain versions; #4 = input is a domain; #5 = framework is a slim domain; #6 = `frame_packet` kept-but-untangled. Encapsulation = inject-at-construction; handle = segregated `INativeHandle` with the honest ceiling.
- **First mechanical step** (no dependency on render v2): cut `frame_packet` from `ecs/system.h` (§9.1).
- **Full vtable audit** (§7.3): enumerate every `ke_*` vtable, classify each member (consumer-called vs. dependency vs. private state), and move everything that isn't a consumer operation into opaque state populated by `create`. Rides along with the per-domain ejection (§9).
- **Supersede** Kanban K1 / K3 / A12 / Bug 1.37 — fold them into the phased ejection above.
- Nothing has been moved yet; this doc is the plan.
