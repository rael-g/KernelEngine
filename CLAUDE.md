# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build commands

### C/C++ (CMake + vcpkg + Ninja + Clang)

```bash
# Configure (run from repo root)
cmake --preset win      # Windows
cmake --preset linux    # Linux

# Build
cmake --build --preset win
cmake --build --preset linux

# Install
cmake --install build/win --prefix build/native
cmake --install build/linux --prefix build/native

# Run a specific example after building
./build/win/bin/01_minimal_log.exe
```

The build output lands in `build/win/bin/` (executables and DLLs) and `build/win/lib/`. The C# native interop layer expects compiled native libraries at `build/native/bin/` (Windows) or `build/native/lib/` (Linux).

### C# (.NET 10)

```bash
dotnet build
dotnet build -c Release
```

### Regenerating C# P/Invoke bindings

ClangSharpPInvokeGenerator is used as a local dotnet tool (see `src/csharp/dotnet-tools.json`). Run from `src/csharp/`:

```bash
dotnet tool restore
```

Then invoke `ClangSharpPInvokeGenerator` against the relevant C headers in `src/c/kernel/include/`.

---

## Architecture overview

Kernel Engine is a **microkernel game engine** with a strict layered architecture:

### Layer 1 — C Kernel (`src/c/kernel`)

The heart of the engine. Pure C with an ABI-stable interface (`extern "C"`). All structs use vtable-style function pointers.

Key types (see `src/c/kernel/include/kernel_engine/kernel/`):
- `ke_allocator` — explicit memory allocation, passed everywhere
- `ke_logger` / `ke_logger_sink` — pluggable logging
- `ke_message_pipe` — async decoupled event bus between services
- `ke_world` / `ke_scene` / `ke_ecs_registry` / `ke_node` — simulation model
- `ke_frame` — per-tick snapshot passed to `ke_world::update`

CMake target: `ke_kernel` (alias `ke::kernel`). Public headers live under `include/`, private implementation under `src/`.

### Layer 2 — C++ plugins (`src/cpp/`)

Concrete implementations of the C kernel interfaces, compiled as shared libraries:
- `src/cpp/window/glfw` — `ke_window_glfw_create` — GLFW-backed window
- `src/cpp/render/bgfx` — `ke_render_bgfx_create` — bgfx-backed renderer
- `src/cpp/render/shader_compiler` — bgfx shader compiler wrapper

Plugins expose only a C factory function (e.g., `ke_window_glfw_create`) so the kernel layer stays unaware of C++ or vendor libraries.

### Layer 3 — C# native bindings (`src/csharp/Native/`)

Auto-generated P/Invoke wrappers (via ClangSharpPInvokeGenerator) for each native target:
- `KernelEngine.Kernel.Native` — wraps `ke_kernel`
- `KernelEngine.Bgfx.Native` — wraps `ke_render_bgfx`
- `KernelEngine.Glfw.Native` — wraps `ke_window_glfw`
- `KernelEngine.ShaderCompiler.Native` — wraps the shader compiler

Generated files live in `Generated/` subdirectories. `NativeDependencies.targets` locates the native DLL at `build/native/` and copies it to the output directory.

### Layer 4 — C# Framework (`src/csharp/KernelEngine.Framework`)

High-level application shell using `Microsoft.Extensions.DependencyInjection`. `Application` is an abstract base class that:
1. Builds the DI container
2. Resolves `Allocator`, `Logger`, `MessagePipe`, `Window`, `Renderer` from DI
3. Creates a `World` (combining allocator + renderer + window)
4. Runs the main loop: `MessagePipe.Pump()` then `World.Update()` each frame

Users subclass `Application` and register concrete services into `IServiceCollection`.

---

## Coding conventions

### C / C++
- **Namespace**: `kernel_engine::domain::<subdomain>::<name>` (C++ only). `using namespace` is forbidden.
- **File extensions**: `.hh`/`.cc` for C++, `.h`/`.c` for C.
- **Naming**: C++ follows Google C++ Style (PascalCase types); C follows Unix conventions (`snake_case` everywhere with `ke_` prefix).
- **Public vs private headers**: Public API headers go in `include/`; private implementation headers stay next to `.cc` files and must not be included externally.
- **All headers** use `#pragma once`.
- **Formatting**: Microsoft C++ style (defined in `.clang-format`).
- **CMake targets** are prefixed `ke_` and aliased with `::` (e.g., `ke::kernel`).
- **C API files**: Components with a stable C API expose it through `*_api.h` / `*_api.cc`.
- **Documentation**: Doxygen-style (`@brief`) for all public C/C++ APIs.

### C#
- XML doc comments (`///`) on all `public` and `protected` members.
- Bindings in `Generated/` are machine-generated; do not edit them by hand.

### Error handling
- Errors are returned as `ke_result` values (first-class, no exceptions in C layer).
- All callers must explicitly handle `ke_result`.

### Memory
- Every major component requires an explicit `ke_allocator*`.
- Raw pointers are non-owning unless documented otherwise.
- Use engine allocators for all plugin-level allocations.

### Git / commits
- All commits must follow Conventional Commits (`feat`, `fix`, `refactor`, `docs`, `test`, `chore`).
- 1 commit = 1 logical task. Never use `git add .`; stage files selectively.
- Do not run destructive git commands without explicit user confirmation.
- Always one line commit.
---

## Key docs

- `docs/Architecture/` — architecture vision documents (01–06)
- `docs/Development/ProjectGuidelines.md` — strict coding standards
- `AGENTS.md` — agent operating rules, design principles, anti-patterns, and output quality requirements
