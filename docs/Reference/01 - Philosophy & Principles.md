# Philosophy & Principles

The architecture is opinionated. These principles are the *why* behind every structural decision in the rest of this reference. When a future change conflicts with one of these, the change is wrong until proven otherwise.

## 1. Microkernel — the core is blind to domains

The kernel knows nothing about "pixels," "collision," or "sound." It is an orchestrator of abstract primitives: memory, logging, an ECS, a frame snapshot, and vtable contracts for capabilities it never implements itself. Every concrete capability (a real renderer, a real window) lives outside the kernel.

This keeps the core small, stable, and long-lived: graphics APIs come and go, but the kernel's contract for "a renderer" does not.

## 2. Building blocks, never built blocks

**The single most important rule.** The kernel provides primitives that compose into features; it never ships the features themselves.

- ✅ In the kernel: ECS, allocator contract, logger contract, `ke_render`/`ke_window` vtables, threading primitives, frame packet.
- ❌ Not in the kernel: a "health system," a "grass renderer," a specific post-processing chain.

Concrete systems grow infinitely with use cases. If each one lived in the kernel, the core would bloat forever. Concrete systems live in higher layers (C++ plugins or the C# framework). When tempted to add something to the kernel, ask: *is this a universal primitive, or a specific feature?* Only primitives belong.

> **Corollary — the escape-hatch test.** When a user hits a wall, ask: is the missing thing **logic/data** or a **capability**? Logic/data (custom AI, mass simulation) is solvable in user-land. A missing capability (GPU instancing, a new collider type) lives below the user's reach and means the engine must extend a *contract* — and it should do so by adding a reusable primitive, not feature-specific code. See [12 - Architecture Backlog & Decisions](12%20-%20Architecture%20Backlog%20%26%20Decisions.md).

## 3. Plugins are substitutable

Every capability is defined by a kernel vtable and implemented by one or more **interchangeable** backend plugins. bgfx is *a* renderer, not *the* renderer. GLFW is *a* window backend. Swapping bgfx for a hand-written Vulkan backend, or GLFW for SDL, is a matter of providing another plugin that satisfies the same contract — no kernel or framework change required.

This is why interfaces never embed backend types: an `IRenderer` that exposed a `bgfx*` would bind every alternate implementation to bgfx, defeating the purpose.

## 4. The engine owns the contract; external libraries do the heavy lifting

For each feature domain there is a universal kernel vtable (owned by the engine) and one or more plugins wrapping a battle-tested external library:

| Domain | Contract (kernel) | External library (plugin) |
|---|---|---|
| Rendering | `ke_render` | bgfx |
| Window | `ke_window` | GLFW |
| Asset loading | `ke_asset_loader` | Assimp |
| Task scheduling | `ke_task_scheduler` | enkiTS |
| Logging | `ke_logger` | Serilog (+ built-in console) |

Engineering effort goes into **API design and integration**, never into reinventing wheels. Exceptions only when no external library fits, all options have license conflicts, or the domain is so trivial that a wrapper is heavier than the implementation (e.g. a console log sink). Future domains (physics → Jolt/Box2D, audio → miniaudio/FMOD, animation → ozz) follow the same pattern.

## 5. Explicit dependency injection — no global state

The engine rejects service locators and singletons. Every dependency — infrastructure (allocator, logger) or domain (a renderer needing a window) — is provided explicitly at construction. The system graph is a transparent, traceable wiring, not a black box. In C# this is expressed through `Microsoft.Extensions.DependencyInjection`; in C, dependencies are passed as parameters to `_create()` functions.

## 6. Explicit memory — no implicit allocator

Every component that allocates takes an `ke_allocator*` via its params. The caller chooses the strategy (malloc, arena, pool) per call site. There is no implicit global heap. This gives domain isolation (one subsystem can't silently bloat another), custom strategies (frame arenas vs long-lived pools), and observability (per-domain memory accounting).

## 7. Failure as a value — no exceptions in the C layer

The C layer returns `ke_result`; callers must handle it. No side-channel error propagation. The managed layer translates results into `KernelResult` / typed `Result<T>` and throws `KernelException` only at the managed boundary where it's idiomatic.

## 8. Stable native boundary

The kernel exposes a clean, ABI-stable C interface (`extern "C"`, vtable-style function pointers). This lets the core be consumed from C, C++, C#, Python, or anything with a C FFI — without coupling the engine's evolution to one high-level language.

## 9. The Framework is a preference, not a law

This is a deliberate, personal stance of the engine's author and deserves emphasis:

> **`KernelEngine.Framework` is the author's *ideal* high-level API — not a mandatory layer, and not the only valid way to use the engine.**

The framework is built in a **different paradigm from the kernel**. The kernel is data-oriented (an ECS of components and systems). The framework presents a **node→ECS** model: an object-oriented scene tree of `Node`s that are thin views over ECS entities (see [06 - Framework](06%20-%20Framework.md)). That is an opinionated authoring choice, chosen for ergonomics — not something the kernel mandates.

A consumer is free to:
- Use the kernel + plugins directly with their own thin layer.
- Replace the framework's threading model, scene model, or node paradigm wholesale.
- Run headless with no renderer or window at all.

The kernel imposes **no** scene model, **no** threading model, and **no** node paradigm. Everything above the C ABI is a choice — the framework is simply the choice the author recommends.

## 10. Minimalism, predictability, longevity

- **Minimalism**: if it doesn't *need* to be in the kernel, it isn't.
- **Predictability**: execution order and resource ownership are deterministic.
- **Longevity**: the architecture stays valid even as specific technologies (graphics APIs, windowing libs) are replaced.
