# KernelEngine — Project Engineering Guidelines

This document is the authoritative reference for project conventions. It is read by every contributor (human or agent) before changing code. When in doubt, this file overrides personal preference.

If a convention seems wrong, propose a change here in a PR — do NOT silently deviate.

---

## 0. Guiding principles

* **Consistency beats cleverness.**
* **Explicit is better than implicit.**
* **Readability and predictability outweigh brevity.**
* **Code is written for other engineers first, compilers second.**

If a choice exists between two valid approaches, the one that reduces ambiguity and variation MUST be preferred.

---

## 1. Architectural principles (non-negotiable)

These five rules govern what goes where. Every contributor MUST be able to recite them.

### 1.1. Public API lives ONLY in `src/c/kernel/include/`

`src/c/kernel/include/` is the sole source of public engine API. Every interface, vtable, struct, enum, and function the engine exposes to consumers (plugins, framework, applications) lives here. C ABI only. C++ plugins under `src/cpp/<plugin>/` expose **exactly one** public C function: `ke_<plugin>_create()`. All other headers in `<plugin>/include/` exist for cross-target sharing within the same plugin (e.g., between `core/` and `device/` sub-libs); anything internal to a single target goes in that target's `src/`.

When in doubt about a header location, ask:
- *"Is this consumed by a different target than the one that defines it?"* If yes → `include/`. If no → `src/`.
- *"Is this a C function declared in a plugin header?"* If yes and it's NOT `_create()` → violation; move to internal.

### 1.2. Kernel = building blocks, NEVER built blocks

The kernel C provides **primitives**: ECS, vtable interfaces (`ke_render`, `ke_window`), allocator contract, logger contract, threading primitives. **It does not provide concrete systems, components, or implementations** — those grow infinitely with use cases and would bloat the kernel forever.

Concrete systems (`MeshSystem`, `LightSystem`, etc.) live in higher-layer plugins (C++ above the kernel, or C# Framework). Concrete sinks (`ConsoleSink`, `SerilogSink`) live in their own plugins. Concrete backends (bgfx, glfw, assimp) live in their own plugins.

The kernel cannot grow with every new feature. If a contributor proposes adding a new system, sink, backend, or implementation to the kernel, the answer is no — it goes in a plugin.

### 1.3. Universal-or-nothing for cross-cutting features

When considering a new capability:

1. *Is it really needed?* If no, drop.
2. *Does std/C++/.NET BCL already provide it cross-platform?* If yes, use that — do NOT wrap.
3. *Can it be implemented on every shipping target?* (Windows, Linux, macOS, iOS, Android, WebGL, consoles)
   * **Yes** → goes in the appropriate layer (kernel if a building block; plugin otherwise). Provide no-op fallback for platforms where it does nothing.
   * **No, but useful for development** (Win/Linux/macOS) → goes in `KernelEngine.DevPlatform.*` plugin. Optional; production builds can skip it.
   * **No, fundamental for some target** → reconsider whether we want it at all.

This rule killed `set_thread_affinity` (forbidden in iOS, restricted in Android) and `JoinTimeout` as PAL methods (resolved with `std::condition_variable`).

### 1.4. No `malloc` directly. Allocators are passed via params

Every component that allocates memory accepts an `ke_allocator*` via its `_params` struct. There is no implicit global allocator. The user picks the allocator (malloc, arena, pool) per call site.

Direct calls to `malloc`/`free`/`new`/`delete` in production code are forbidden outside of:
- The implementation of `ke_allocator` itself.
- C++ STL containers used in implementation files (transitive — STL allocators are accepted).

If a piece of code "doesn't have an allocator yet", that is a sign the function should accept one as a parameter, not a sign that `malloc` is acceptable.

### 1.5. No "factory" naming for non-polymorphic functions

A **factory** (`_create()`) returns a polymorphic object with vtable + lifecycle (destroy + state). Examples: `ke_render_bgfx_create`, `ke_window_glfw_create`, `ke_thread_std_create`.

A function that just **fills a struct** with function pointers is NOT a factory — even if it looks similar. Name it `_init`, `_describe`, `_register`, etc. Don't use the same word for two different patterns; readers stop trusting the term.

---

## 2. Plugin architecture

### 2.1. Plugin entry point

Every C++ plugin under `src/cpp/<plugin>/` exposes **exactly one** public C function:

```c
KE_<MODULE>_API ke_result ke_<plugin>_create(const ke_<plugin>_params* params, ke_<interface>** out);
```

Examples:
- `ke_render_bgfx_create(const ke_render_bgfx_params*, ke_render**)`
- `ke_window_glfw_create(const ke_window_glfw_params*, ke_window**)`
- `ke_thread_std_create(ke_allocator*, const ke_thread_params*, ke_thread**)` *(legacy: takes allocator separately; new plugins put it in params)*

The output is always a pointer to a kernel-defined vtable struct (`ke_render`, `ke_window`, etc.). The plugin owns the impl behind `handle`; the kernel sees only the vtable.

### 2.2. Vtable struct pattern

Every "interface" struct in the kernel uses this shape:

```c
typedef struct ke_<interface> {
    void *handle;                                       // FIRST field — opaque impl pointer
    void (*destroy)(struct ke_<interface> *self);       // self always FIRST arg
    ke_result (*method_a)(struct ke_<interface> *self, /* args */);
    /* more methods */
} ke_<interface>;
```

Rules:
* First field MUST be `void *handle`.
* First arg of every function pointer MUST be `struct ke_X *self`.
* Vtable structs MUST NOT expose internal pointers (allocator, logger, state) as public fields. Those live inside `handle`. Bug 1.37 documents the current violation in `ke_input`.
* Methods that can fail return `ke_result`. Methods that cannot fail return `void`.
* The `destroy` method is mandatory.

### 2.3. `_params` struct convention (parameter bags)

Functions that take 4+ configuration fields (or fewer with high probability of growth) accept a `_params` struct:

```c
typedef struct ke_<plugin>_params {
    size_t                struct_size;     // FIRST: for ABI versioning (Phase O)
    struct ke_allocator  *allocator;       // SECOND: required for any plugin that allocates
    struct ke_logger     *logger;          // THIRD: optional (NULL accepted) if plugin logs
    /* domain-specific config fields */
} ke_<plugin>_params;
```

Rules:
* Suffix is **always `_params`**. Forbidden synonyms: `_desc`, `_descriptor`, `_info`, `_config`, `_options`. (Avoid collision with the technical "descriptor" concept from Vulkan/D3D.)
* `struct_size` first (when ABI versioning is implemented in Phase O).
* `allocator` second (if needed). `logger` third (if used).
* Then domain-specific fields, ordered logically (related fields grouped).
* `const char*` fields are **owned by caller**; **callee must deep-copy** before storing. Caller is free to free its memory after the call returns.

When NOT to use a `_params` struct:
- Function with 1–3 mandatory fields, no growth expected → individual params.
- Internal C++ helper class → constructor parameters.
- C# DI extension (`AddBgfxRenderer(string shaderPath, bool vsync = true)`) → named arguments with defaults.

### 2.4. Per-plugin export macro: `KE_<MODULE>_API`

Each plugin defines its own export macro in a header at the root of its `include/`:

```c
// src/cpp/<plugin>/include/<module>_export.h
#pragma once

#ifndef KE_<MODULE>_API
#  if defined(_WIN32) || defined(__CYGWIN__)
#    ifdef KE_<MODULE>_EXPORT
#      define KE_<MODULE>_API __declspec(dllexport)
#    elif defined(KE_<MODULE>_STATIC)
#      define KE_<MODULE>_API
#    else
#      define KE_<MODULE>_API __declspec(dllimport)
#    endif
#  else
#    define KE_<MODULE>_API __attribute__((visibility("default")))
#  endif
#endif
```

Rules:
* **Never** use the kernel's `KE_API` from a plugin — define your own.
* Plugins MUST define `KE_<MODULE>_EXPORT` in their CMakeLists when building the shared lib.
* Convention TBD (track W.14): `<module>_export.h` location. Currently inconsistent — some at `include/` root (`render_export.h`), some nested (`threading_export.h`). Pick one and apply.

### 2.5. Plugin → Layer mapping (folder structure)

```
src/c/kernel/                        ← Layer 1: pure C kernel (interfaces only)
src/cpp/<plugin>/                    ← Layer 2: C++ plugin implementing a kernel interface
  include/kernel_engine/<domain>/<plugin>/<plugin>.h    ← single public C header
  src/                               ← all impl + private .hpp
src/csharp/KernelEngine.<X>/         ← Layer 3 + 4 combined per plugin
  Native/                            ← auto-generated bindings (after W.15 refactor)
  ServiceCollectionExtensions.cs     ← DI registration
  *.cs                               ← managed wrappers
src/csharp/KernelEngine.Kernel/      ← managed wrappers for the C kernel
src/csharp/KernelEngine.Framework/   ← orchestration (Application, default scenes, etc.)
```

---

## 3. C++ and C code conventions

### 3.1. File extensions

* C++ headers: `.hpp`
* C++ implementation: `.cpp`
* C headers: `.h`
* C implementation: `.c`
* `.hh`, `.cc`, `.cxx` are **forbidden**. (Bug 1.32 tracks current violations.)

### 3.2. File naming

* Files MUST use `snake_case`. (Bug 1.33 tracks current violations: `KeThread.cpp`, `AssimpLoader.cpp`, etc.)
* Header/source pairs MUST match the primary type name (in snake_case).

### 3.3. Header discipline

* All headers MUST use `#pragma once`.
* Public headers (API) live in `include/`. Private headers live next to the `.cpp` files.
* **Never mix C ABI declarations (`extern "C"`) and C++ class declarations in the same public header.** Use a `.h` for the C ABI portion and a separate `.hpp` for the C++ class. Bug 1.31 documents the violation in `bgfx_shader_compiler.hh`.
* A public header MUST NOT include implementation details. Forward-declare and PIMPL when necessary.

### 3.4. Namespaces (C++)

* All C++ code lives inside `kernel_engine::<domain>::<subdomain>?::<name>`.
* Namespaces SHOULD align with the physical directory structure (e.g., `src/cpp/render/core/` → `kernel_engine::render::core`).
* `using namespace` is **strictly forbidden** (Bug 1.34 tracks current violations).
* `using X::specific_type` declarations are RECOMMENDED in `.cpp` files to shorten qualified names. They MUST appear at the top of the file, BEFORE the namespace block.
* `using` declarations are forbidden in header files.

### 3.5. Naming conventions

* **C++**: follows **Google C++ Style Guide** (PascalCase for types, camelCase or snake_case per Google for variables and methods). Filenames are snake_case (overrides Google).
* **C**: follows Unix conventions — snake_case for functions, types, variables. All public symbols prefixed with `ke_`.

### 3.6. Error handling

* C: every fallible function returns `ke_result`. No exceptions in C layer.
* C++: prefer `ke_result`; throw only for programmer errors (precondition violations).
* All callers MUST handle `ke_result`. Do not discard with `(void)result` unless an explicit comment justifies why.

### 3.7. Memory and ownership

* Ownership MUST be explicit. Document with comments when a pointer is owning vs borrowed.
* Raw pointers represent non-owning references unless documented otherwise.
* Prefer engine allocators (`ke_allocator`) over `malloc`/`new`. See § 1.4.

### 3.8. Build system

* CMake logic MUST be deterministic and explicit.
* Every module MUST define its own target, prefixed `ke_` (e.g., `ke_kernel`, `ke_render_bgfx`).
* Targets SHOULD be exposed using CMake aliases with `::` (e.g., `ke::kernel`).
* Plugin-specific options should compile gated (e.g., `KE_DEV_PLATFORM_EXPORT`).

### 3.9. Formatting

* C++ adheres to **Microsoft C++ style** for indentation and braces (`.clang-format`).
* Clang-tidy fixes that change logic or break established C patterns are NOT to be applied automatically.

---

## 4. C# layer conventions

### 4.1. Project naming

* Plugins: `KernelEngine.<Domain>.<Backend>` (e.g., `KernelEngine.Render.Bgfx`, `KernelEngine.Window.Glfw`, `KernelEngine.DevPlatform.Win32`).
* Auto-generated bindings live INSIDE the plugin project at `Native/` (after W.15 refactor; today they live in `src/csharp/Native/KernelEngine.<X>.Native/`).
* Standard .NET naming applies (PascalCase for types, methods, properties; camelCase for parameters and locals).

### 4.2. Wrapper class naming

* Managed wrappers around native types use `Kernel<Concept>` (e.g., `KernelThread`, `KernelException`, `KernelSemaphore`, `KernelTask`). **Not** `KeXxx`. (W.14 fixes the `KeTask` outlier.)

### 4.3. Handle wrappers

Every native handle (`ke_*_handle`) is wrapped as a `readonly record struct` with `None` and `IsValid`:

```csharp
public readonly record struct MeshHandle(uint Value)
{
    public static readonly MeshHandle None = new(uint.MaxValue);
    public bool IsValid => Value != uint.MaxValue;
}
```

* Sentinel for "none" is always `uint.MaxValue`.
* Handle `0` is reserved for engine built-ins (e.g., `TextureHandle.White`) when applicable.

### 4.4. Component types (ECS)

Components are simple value structs with `[StructLayout(LayoutKind.Sequential)]` and PascalCase + `Component` suffix:

```csharp
[StructLayout(LayoutKind.Sequential)]
public struct TransformComponent
{
    public Vector3 Position;
    public Quaternion Rotation;
    public Vector3 Scale;
}
```

* Memory layout MUST match the corresponding `ke_*_component` struct exactly.
* Components MUST NOT have behavior (no methods beyond constructors). Behavior lives in systems.

### 4.5. DI extension methods

Each plugin exposes a static extension class `ServiceCollectionExtensions` with `AddXxx()` methods:

```csharp
public static IServiceCollection AddBgfxRenderer(
    this IServiceCollection services,
    string shaderPath,
    bool vsync = true)
{
    services.AddSingleton<Renderer>(sp => /* construct from sp.GetService<Allocator>() etc. */);
    return services;
}
```

* Constructor parameters use named arguments with defaults (no `_params` struct in C# DI).
* Resolve `Allocator`, `Logger?` etc. from `IServiceProvider`.
* Error messages MUST NOT hardcode backend names. Bug 1.40 (track W.14) covers existing violations like `"AddBgfxRenderer"` literal in `Application.cs`.

### 4.6. Result vs throw

* **Default**: return `Result<T>` for any operation that can fail in normal use.
* **Throw**: only for programmer errors (`ObjectDisposedException`, precondition violations, kernel asserts).
* `KernelException.ThrowIfFailed(result)` converts a `ke_result` into an exception when the caller wants throw-style semantics.
* Current pain point (tracked in Y.4 + Phase R): `ke_result` is too coarse. Until enriched, document at the call site why a generic error is acceptable.

---

## 5. Anti-patterns (forbidden / discouraged)

| Anti-pattern | Why bad | Use instead |
|---|---|---|
| `using namespace` | Pollutes scope, hides origin | `using X::specific_type` decl |
| Naming non-polymorphic functions `_create` / `factory` | Misleads readers about lifecycle | `_init`, `_describe`, `_register` |
| `_desc` / `_descriptor` / `_info` / `_config` / `_options` suffix | Inconsistent; collides with graphics descriptor concept | `_params` |
| Vtable struct exposing `allocator`/`logger` as public fields | Leaks impl state; breaks abstraction | Keep in `handle` impl |
| Plugin header exporting C functions other than `_create()` | Breaks layer boundary; couples consumers to backend | Add to `ke_<interface>` vtable in kernel |
| Class declaration in a plugin's public C ABI header | Mixes idioms; consumers can't include if pure C | Move class to private `.hpp` |
| `KE_API` (kernel macro) used by a plugin | Couples plugin to kernel exports | Plugin defines own `KE_<MODULE>_API` |
| Cargo-cult macros declared "for future use" | Becomes dead code; misleads readers | Add when there's a real consumer |
| Hardcoded backend names in framework messages (`"AddBgfxRenderer"`) | Couples Framework to specific backend | Generic message or message via DI |
| Direct `malloc`/`new`/`free` in production code | Bypasses allocator contract; breaks telemetry/testing | Pass `ke_allocator*` through `_params` |
| `.hh` / `.cc` / `.cxx` extensions | Inconsistent | `.hpp` / `.cpp` |
| PascalCase filenames | Inconsistent | snake_case |
| Suffix `_public` on a header in `include/` | Redundant — `include/` IS public | Drop the suffix |

---

## 6. Comments

* Comments explain **why**, not **what**.
* Comments MUST NOT narrate changes (no "changed X to Y in commit Z") or restate code.
* Use `///` doc-comments on public APIs; explain the contract, not the implementation.
* Mark non-obvious intentional choices (`// Intentional: reasoning`).

---

## 7. Process

* Before adding a new convention here, propose it in a PR with rationale.
* Before deviating from a convention, propose the change here first. Do not write inconsistent code.
* When auditing junior agent output (or your own code from yesterday), apply the rules in this document strictly. Build passing ≠ correct.
* The Kanban (`docs/Kanban.md`) tracks active and pending work. The Backlog (`docs/Architecture/08 - Engine Architecture Backlog.md`) preserves design rationale and the bug catalog. This document (`ProjectGuidelines.md`) is the rule reference.
