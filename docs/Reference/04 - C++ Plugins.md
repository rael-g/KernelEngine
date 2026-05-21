# C++ Plugins

Plugins are where concrete capability lives. Each is a C++ shared library that implements one kernel vtable contract and exposes it through **exactly one** public C function. They are the substitutable backends of Principle 3.

## The plugin contract

A plugin exposes one public C-ABI entry point:

```c
ke_result ke_<plugin>_create(const ke_<plugin>_params* params, ke_<contract>** out);
```

- It takes a `_params` bag (allocator, logger, backend-specific options).
- It returns a kernel vtable pointer (`ke_render*`, `ke_window*`, …) — a polymorphic object with function pointers + lifecycle.
- Everything else in the plugin is private. `.hpp` files with C++ classes, internal helpers, and state are **implementation detail** that consumers must never include.

This is why the boundary rule (see [02 - Layered Architecture](02%20-%20Layered%20Architecture.md)) is non-negotiable: a plugin's public surface is a single small `.h`. If a generic utility is tempting to expose, it belongs in the kernel (in C), not in a plugin header.

Naming: C++ uses `PascalCase` types (Google C++ Style); namespaces are `kernel_engine::domain::subdomain` (e.g. `kernel_engine::render::bgfx`). `using namespace` is forbidden in headers. `_create()` is reserved for functions that return a polymorphic vtable object; a function that merely fills a struct is `_init`/`_describe`/`_register`, not a factory.

## Current plugins

| Plugin | Path | Factory | Contract | External lib | Status |
|---|---|---|---|---|---|
| bgfx renderer | `src/cpp/render/bgfx/` | `render_bgfx_create()` | `ke_render` | bgfx | ✅ |
| GLFW window | `src/cpp/window/glfw/` | `ke_window_glfw_create()` | `ke_window` | GLFW | ✅ |
| Assimp asset loader | `src/cpp/asset/assimp/` | `asset_loader_assimp_create()` | `ke_asset_loader` | Assimp | ✅ |
| bgfx shader compiler | `src/cpp/render/bgfx_shader_compiler/` | (compiler entry) | `ke_shader_compiler` | shaderc | ✅ |
| enkiTS scheduler | `src/cpp/task_scheduler/enki/` | scheduler create | `ke_task_scheduler` | enkiTS | ✅ |
| Threading impl | `src/cpp/threading/` | (primitives) | `ke_thread`/`ke_semaphore`/`ke_frame_sync` | std::thread | ✅ |
| Dev platform | `src/cpp/dev_platform/` | dev platform create | `ke_dev_platform` | OS (Win32) | 🚧 Win32 only |

## The bgfx render plugin (internal structure)

The renderer is the largest plugin and is internally split into sub-libraries (still one public entry point):

- **`render/contract/`** — abstract `GpuDevice` contract (`gpu_device.hpp`) and GPU types, backend-agnostic.
- **`render/core/` (`ke_render_core`)** — agnostic pipeline support: `CoreRenderer`, `GeometryManager`, `TextureManager`, `LightingManager`, `ShadowPipeline`, `PostProcessPipeline`, `ClusteredForward`, `FrameSubmitter`, `ShaderProvider`. Consumes `ke_frame_packet` and issues draw calls.
- **`render/bgfx_device/`** — the concrete `BgfxGpuDevice` implementing `GpuDevice` via bgfx.
- **`render/bgfx/`** — the public `render_bgfx_create()` wiring it all together.

`FrameSubmitter` is the piece that takes a frame packet and turns it into bgfx draw calls on the render thread. See [07 - Graphics & Rendering](07%20-%20Graphics%20%26%20Rendering.md).

> Note: `ke_render_core` is an internal C++ library consumed by the bgfx plugin via headers; it has **no** public C ABI. (An earlier `render_core.h` public header was removed; the render *systems* now live in C# — see [07](07%20-%20Graphics%20%26%20Rendering.md).)

## The Assimp asset plugin

`src/cpp/asset/assimp/` loads models via Assimp and decodes textures, producing `ke_model_data` (meshes as `ke_vertex` arrays, materials, RGBA8 textures) behind the `ke_asset_loader` contract. The managed wrapper exposes this as `IModel` (see [09 - Assets & Pipelines](09%20-%20Assets%20%26%20Pipelines.md)).

## Dev platform plugin

`src/cpp/dev_platform/` provides optional, dev-only OS facilities — currently OS thread naming, with crash handler / minidump support planned. It is intentionally separate because these are platform-specific (Principle: universal-or-nothing — platform-specific facilities go in a dev-only plugin, not the kernel).

## Substitutability in practice

To add a new backend for any domain:
1. Implement the kernel vtable in a new `src/cpp/<plugin>/`.
2. Expose one `ke_<plugin>_create()`.
3. Generate C# bindings + add a thin wrapper assembly with an `.AddXxx()` DI extension.

No kernel change, no framework change. The bgfx renderer could be replaced by a direct Vulkan backend, or GLFW by SDL, this way. Future domains (physics → Jolt/Box2D, audio → miniaudio/FMOD, animation → ozz) will each be a kernel vtable + one or more such plugins — see [11 - Roadmap & Vision](11%20-%20Roadmap%20%26%20Vision.md).
