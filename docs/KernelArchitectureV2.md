# Kernel Architecture V2 — What Is Allowed to Live in the Kernel

**Status**: Doctrine accepted and arc complete (2026-06-18, branch `feat/kernel-v2`). Domain ejection done (`src/c/kernel/` deleted); `ke_kernel` meta-target deleted; `ke_allocator` vtable abolished (plain functions); `ke_X_handle` ownership model shipped (destroy only in handles, never vtables); full vtable audit done; `spatial` data contract extracted; §5 phase model confirmed. See §12 Delivered table for commit-level detail.

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
| **2 — Foundation (domain-agnostic primitives)** | *Is it a generic utility anyone uses, imposing no domain?* | allocator, logger, `common/` (containers, math, hash, handles, error), `resource_cache`, `scheduler`, shared **data contracts** |
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

- `allocator`, `logger`, `common/`, `resource_cache`, `scheduler` — generic, no domain opinion.
- **Shared data contracts** (§3.2): `spatial` (transform, future aabb/bounds). POD headers, no impl.
- `resource_cache` is already correctly type-erased — it keys `void*` by path with a refcount and a destructor callback. It does **not** know what a "texture" is, and must never learn. *Resource kinds* are owned by whoever owns them; loaders (assimp, stb_image) are domain plugins; the cache is a generic primitive, like a hash map.

### 4.3 Tier 3 — Domains

Each domain is self-contained:

- **One behavior contract** (vtable), header-only, static-linked. *(APIs are not DLLs; only implementations are.)*
- **One or more implementations** (the DLLs): bgfx renderer, miniaudio, Box2D, GLFW window, …
- **Its own C# binding project** — one per domain, generated via `scripts/generate_bindings.cs`. One contract → one `.rsp` → one binding csproj.
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

### 7.2 Allocator doctrine (A12.1) — **resolved**

`ke_allocator` is an **internal implementation utility**, not a public API and not a factory parameter.

**Decision:** all C domain implementations use `ke_allocator` internally (as a PRIVATE CMake dep). Factory functions do **not** accept `ke_allocator*` as a parameter — the caller has no say in the allocation strategy.

Rationale:
- Third-party libs (bgfx, GLFW, Box2D, assimp, stb, flecs) bypass our allocator entirely. Pretending we have "full memory control" is fiction; we control our own allocations and document where third-party leakage occurs.
- The single point of change for the underlying heap is `allocator_malloc.c` — one file, one place. All C impls inherit the change. This is the real benefit; passing `ke_allocator*` externally buys nothing and pollutes every factory signature.
- Debug leak detection for C impls: ASan (`-fsanitize=address`) or LeakSanitizer. No proxy allocator exists — the allocator is plain functions, not a vtable, so there is no per-impl "report at destroy" hook to wire. Each impl links `ke_allocator_malloc` PRIVATE; ASan instruments the underlying `malloc`/`free` calls directly.
- C++ implementations use RAII / standard containers; `ke_alloc`/`ke_free` do not apply to them. Debug leak detection via ASan / Valgrind.

**What changes from the old rule:** `ke_allocator*` disappears from all `_params` structs and factory signatures. It becomes an `#include`-only, link-PRIVATE concern of each C implementation.

**Refinement (PO, 2026-06-17) — drop the vtable shape entirely.** Because the allocator is no longer an API surface (nobody outside an impl ever holds one), there is no reason for it to be a vtable-of-function-pointers with a `create`/`destroy` lifecycle. The indirection only exists to allow swapping implementations *across an ABI boundary* — and there is no boundary here. So the allocator collapses to a **traditional plain-function module**: header + implementation as one compiled unit (not an interface lib), exposing ordinary functions (`ke_alloc(size, align)` / `ke_free(ptr)` / …), linked directly (PRIVATE) by whoever needs it. No `ke_allocator` struct, no `void* handle`, no `(*destroy)` slot, no factory. The header must state plainly that this is an internal utility, not engine API.

Consequence for §7.3 (the `ke_X_handle` ownership pass): **the allocator is excluded from the handle refactor.** It does not get a `ke_allocator_handle` — it stops being a vtable at all. The handle model applies only to the genuine cross-binding behavior contracts (ecs, runtime, render, window, audio, physics, …). This allocator reshape (vtable → plain functions, full internalization, de-parameterization of every factory that currently takes `ke_allocator*`) is its own task, tracked separately from the handle pass.

### 7.3 Ownership doctrine — `ke_X_handle` vs `ke_X*` (resolved 2026-06-17)

**Rule: who creates, owns. Factory methods receive borrows; the host holds the full owner pair.**

Every `ke_*` vtable today carries a `(*destroy)(self)` slot. This creates a double-destroy hazard: any factory that receives a `ke_ecs*` (or any other vtable pointer) as a dependency *can* call `->destroy` on a borrowed reference. The fix is to make that physically impossible.

**Decision — `ke_X_handle` (owner wrapper):**

```c
// ke_ecs.h — consumer vtable, NO destroy slot
typedef struct ke_ecs {
    ke_result (*register_component)(struct ke_ecs*, ...);
    // ... all operation slots ...
    // NO (*destroy)
} ke_ecs;

// Owner wrapper — only the host holds this
typedef struct ke_ecs_handle {
    ke_ecs* ref;                  // borrow — passed to factory deps
    void  (*destroy)(ke_ecs*);   // impl-specific; set by create
} ke_ecs_handle;
```

Factory signatures change from `ke_ecs** out_ecs` to `ke_ecs_handle* out_handle`.
Consumers (factory deps) only see `ke_ecs*` — no `->destroy` slot, so the mistake doesn't compile.
The host calls `handle.destroy(handle.ref)` at shutdown.

**Scope:** the 22 genuine cross-binding vtables that currently carry `(*destroy)` (asset_loader, asset_resolver, image_loader, audio, ecs, input_actions, scene_loader, scene_tree, world, input, logger, physics_2d, render, render_graph, shader_compiler, resource_cache, runtime, scheduler, font_loader, frame_sync, window — and `logger_sink`, which is value-owned by its logger and keeps `destroy` as an *internal* lifecycle, see note). Each loses its `destroy` slot; each factory acquires a matching `ke_X_handle`; all call sites move from `->destroy(self)` to `handle.destroy(handle.ref)`. **`ke_allocator` is explicitly excluded** — per §7.2 it stops being a vtable altogether (plain-function module), so there is no `ke_allocator_handle`.

**Note on `logger_sink`:** `ke_logger_sink` is passed *by value* into `ke_logger.add_sink` and the logger owns it thereafter — it is not a host-held factory product. Its `destroy` is an internal lifecycle the logger invokes on its own teardown, not a cross-binding ownership hazard. It keeps `destroy` in its struct and does **not** get a handle.

**Note on `frame_sync`:** its current `destroy` takes `(self, ke_allocator*)` — an allocator-coupled signature that predates A12.1 doctrine. The `ke_X_handle` migration removes the slot from the vtable AND drops the allocator argument from the destroy call (allocator is internal to the impl per §7.2).

### 7.4 The full vtable audit

The corollaries above don't apply themselves. Every `ke_*` vtable in the codebase predates this doctrine and was written under the "vtable = class" mental model, so the offenses are spread everywhere, not concentrated in one struct. This warrants a **complete, exhaustive sweep of every vtable the engine declares** — not a spot-fix of the allocator field.

**Scope:** every `typedef struct ke_*` that holds function pointers — across the kernel *and* every domain (render, window, audio, physics, input, text, asset, framework, runtime, ecs, scheduler, resource_cache, logger). Enumerate them first (`grep` the public headers for vtable shapes); the list is the audit's checklist.

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
| `context/{allocator,types}.h`, `logger/*`, `common/*`, `resource_cache/*`, `scheduler/*` | 2 | **Stay** (foundation; revisit a separate target only if earned) |
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

**Doctrine**: accepted. Forks resolved: #1 = opaque phases; #2 = static contracts + per-domain bindings; #3 = per-domain versions; #4 = input is a domain; #5 = framework is a slim domain; #6 = `frame_packet` kept-but-untangled. Encapsulation = inject-at-construction; handle = segregated `INativeHandle` with the honest ceiling.

### Delivered (branch `feat/kernel-v2`)

| Item | Commit | What landed |
|---|---|---|
| §9 Domain ejection — all domain headers out of `src/c/kernel/include/` | `44975af` | render, audio, physics, input, window, text, asset, framework each in own `src/c/<domain>/` |
| Render components + `material_file` → render domain | `b756d94` | `ke_camera_component` etc. live in `src/c/render/` |
| `ke_kernel` meta-target deleted; per-domain SHARED DLLs | `69fc5b3`, `b21e0bb` | each domain is its own CMake target + DLL |
| C# projects reorganised into per-domain subdirectories | `fb874b8` | `src/csharp/<domain>/` layout |
| §7.2 Allocator doctrine — `ke_allocator*` removed from all factory signatures | `a2d6ab2` | no factory takes an allocator parameter |
| C# bindings + managed layer adapted to new factory signatures | `f011bc4`, `16c2efe` | ClangSharp regen + wrapper Dispose updates |
| `ke_bool` replaces `bool` in all vtable slots and ABI-crossing structs | `55c3a84` | ABI-safe boolean type across the board |
| `ke_result` + `ke_error` + `ke_error_type` design; `KE_ERROR_SET`/`KE_ERROR_WRAP` macros | `5d7576b`, `22773fb` | typed error singletons, chained cause/file/line |
| §7.3 `ke_X_handle` ownership model — destroy removed from 22 vtables; factories return owner handle | `d234bda` | 22 vtables + all factories + all impls + C# Dispose + regen + 264/264 tests |
| §9.1 `frame_packet` tentacle cut — `ecs/system.h` no longer mentions `frame_packet` | (domain ejection, `44975af`) | `frame_packet` lives in `src/c/render/` only |
| §7.4 vtable audit — `ke_allocator*` removed from `create_render_graph` slot | `a47dff1` | only genuine violation found; C# bindings regenerated |
| §6 `spatial` data contract — `ke_transform_component` in `src/c/spatial/`; `ke_render → ke_spatial` CMake dep wired | `d571323` | `render/components.h` includes `spatial/transform.h`; DAG `render→spatial`, `framework→spatial` correct |
| §7.2 allocator plain-function module — `ke_allocator` vtable abolished; replaced by plain `ke_alloc/ke_free/ke_realloc` + concrete `ke_arena`; C# managed rewrite via `NativeMemory` | `9b87376` | 129 files; all factories drop `ke_allocator*` param; `ke_allocator_malloc` static PRIVATE per impl |
| §7.4 vtable audit — stale `(*destroy)` slots removed from `ke_asset_loader`, `ke_image_loader`, `ke_physics_2d`, `ke_font_loader` | `d0ec43f` | 4 vtables cleaned; handle `destroy` already owned the teardown |
| §5 phase model — enum kept, §5 acid test passes; decision recorded in Pending table | — | No code change; policy decision only |

### Pending

| Item | Doc ref | Notes |
|---|---|---|
| §5 Opaque phases — **closed**: `ke_phase` enum kept as-is; passes the §5 acid test (no domain names baked in — UPDATE/PRE_UPDATE are generic scheduling primitives, not domain identifiers). `KE_PHASE_EXTRACT` removed (never implemented; render V2 reads ECS directly). STARTUP/SHUTDOWN are unimplemented but correct by design (R2+). Opaque-ID approach rejected for V1: no user-defined phases in roadmap, DLL-exported constants would add ABI friction for zero benefit. | §5, open question #2 | Decision 2026-06-18; EXTRACT removed 2026-06-19 |
| §8 Per-domain versioning — deferred to when project-level versioning is implemented | §8, open question #1 | Not blocking merge |
