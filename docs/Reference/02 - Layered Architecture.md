# Layered Architecture

KernelEngine is built as strict layers. Dependencies flow **downward only**; each layer knows about the one below it through a contract, never the reverse.

## The layers

| # | Layer | Location | Language | Role |
|---|---|---|---|---|
| 1 | C Kernel | `src/c/kernel/` | C (ABI-stable) | Primitives + vtable contracts |
| 2 | C++ Plugins | `src/cpp/` | C++ | Backend implementations behind a single C factory |
| 3 | C# Native bindings | `<project>/Native/Generated/` | C# (generated) | P/Invoke over the C ABI |
| 4a | C# Wrappers + Abstractions | `KernelEngine.Kernel(.Abstractions)` | C# | Managed contracts + concrete wrappers |
| 4b | C# Framework | `KernelEngine.Framework` | C# | High-level node→ECS authoring API |

## Layer 1 — C Kernel

The sole source of the public engine API. Every interface, vtable, struct, enum, and function the engine exposes lives under `src/c/kernel/include/`. Pure C, `extern "C"`, vtable-style function pointers. CMake target `ke_kernel` (alias `ke::kernel`). Detailed in [03 - C Kernel](03%20-%20C%20Kernel.md).

## Layer 2 — C++ Plugins

Each plugin is a shared library exposing **exactly one** public C function: `ke_<plugin>_create()`. Everything else in the plugin (`.hpp` classes, internal helpers, private state) is implementation detail that consumers must never include. Detailed in [04 - C++ Plugins](04%20-%20C%2B%2B%20Plugins.md).

### The layer-boundary rule (non-negotiable)

- `src/c/kernel/include/` is the **only** place public engine API lives. C ABI only.
- Each `src/cpp/<plugin>/` exposes one and only one thing publicly: its `ke_<plugin>_create()` entry point, declared in a single small public header.
- All other headers under a plugin (`include/` or `src/`) are implementation detail.
- A generic utility (thread naming, math, logging helpers) belongs in the kernel (implemented in C), never in a plugin's public header.
- Auditing red flag: any `.h` (not `.hpp`) under `src/cpp/<plugin>/include/` containing more than the create function is a violation.

## Layer 3 — C# Native bindings

Auto-generated P/Invoke wrappers (ClangSharp) over the C ABI. They live under a `Native/Generated/` subtree **inside each managed wrapper project** (e.g. `KernelEngine.Kernel/Native/Generated/`), in a `*.Native` namespace (e.g. `KernelEngine.Kernel.Native`). Generated from `.rsp` files; **never hand-edited**. Regenerate via `scripts/generate_bindings.py`. See [05 - C# Layers](05%20-%20C%23%20Layers.md) and [10 - Build & Tooling](10%20-%20Build%20%26%20Tooling.md).

> Note: earlier docs described these as standalone `*.Native` *projects*. The current layout folds them into their parent managed project as `Native/Generated/` folders; the `*.Native` *namespace* remains.

## Layer 4a — C# Abstractions + Wrappers

This layer is split deliberately, and the split is the backbone of the engine's "game devs never touch building blocks" goal:

- **`KernelEngine.Kernel.Abstractions`** — pure contracts. Interfaces (`IRenderer`, `IWindow`, `IWorld`, `IEcsRegistry`, `IResourceFactory`, `IFramePacket`, `IInputReader`, `IAssetLoader`/`IModel`, …) plus pure-managed POCOs and value types (`Vertex`, `Transform`, light records, handles, `Result`/`KernelResult`). **Zero `unsafe`, zero native pointers.** This is the **building-blocks API**.
- **`KernelEngine.Kernel`** — concrete wrappers that own the native pointers (`private`) and implement the Abstractions interfaces. The unmanaged surface is fully encapsulated; nothing leaks a `ke_X*` across the boundary.

Why the split exists: it lets the framework (and game code) depend **only** on `Abstractions`, never on the concrete `Kernel` assembly. The concretes are wired in via dependency injection; consumers see interfaces. This is a hexagonal / ports-and-adapters arrangement — Abstractions are the ports, the `Kernel` wrappers and plugin assemblies are the adapters.

Plugin wrapper assemblies (`KernelEngine.Render.Bgfx`, `KernelEngine.Window.Glfw`, `KernelEngine.Asset.Assimp`, …) reference the concrete `Kernel` (engine-internal) and register their implementations into DI behind the Abstractions interfaces.

## Layer 4b — C# Framework

The high-level, opinionated authoring API: `Application`, `Scene`, `Node` and its typed subclasses, and the render systems. It is built in a **different paradigm** from the kernel — an OOP node tree (node→ECS) rather than raw ECS — and references **only `KernelEngine.Kernel.Abstractions`**, never the concrete kernel or any plugin. It obtains everything through interfaces and an `IEngineHost` factory façade. Detailed in [06 - Framework](06%20-%20Framework.md).

## Who depends on what

```
Game code ─────────────► Framework ───► Abstractions
                                            ▲   ▲
Plugin wrappers (Bgfx, Glfw, Assimp…) ──────┘   │  (register impls into DI)
        │                                       │
        ▼                                       │
   Kernel (concrete wrappers) ──────────────────┘  (implements Abstractions)
        │
        ▼
   Native bindings ───► C ABI ───► C Kernel ◄─── C++ Plugins (via ke_*_create)
```

Key invariants:
- **Game code** imports `Framework` + `Abstractions` only. It imports plugin assemblies *solely* to call their `.AddXxx()` DI-registration extensions — never to use their concrete types.
- **Framework** imports `Abstractions` only.
- **Plugin wrappers** may use the concrete `Kernel` (they are engine-internal adapters).
- **No interface** in `Abstractions` exposes a native pointer.

## The "game dev surface" goal

The north star: a game developer writes against `Framework` + `Abstractions` and never sees a handle, a native pointer, a component ID, or a backend type. Where that goal currently leaks (raw GPU resource creation, per-frame render config, magic keycodes, entity IDs) is tracked as the Framework High-Level API initiative — see [06 - Framework](06%20-%20Framework.md) and [11 - Roadmap & Vision](11%20-%20Roadmap%20%26%20Vision.md).
