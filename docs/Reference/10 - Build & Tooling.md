# Build & Tooling

KernelEngine is a polyglot build: a C/C++ native side (CMake) and a .NET side (dotnet), bridged by generated bindings and deployed native DLLs.

> Deeper detail lives in [`../Development/BuildSystem.md`](../Development/BuildSystem.md), [`../Development/CiCdStrategy.md`](../Development/CiCdStrategy.md), [`../Development/LoggingStrategy.md`](../Development/LoggingStrategy.md), [`../Development/VersioningStrategy.md`](../Development/VersioningStrategy.md), and conventions in [`../Development/ProjectGuidelines.md`](../Development/ProjectGuidelines.md).

## Native (C/C++) — CMake + vcpkg + Ninja + Clang

```bash
cmake --preset win        # configure (Windows);  linux preset for Linux
cmake --build --preset win
cmake --install build/win --prefix build/native   # required so C# finds native DLLs
ctest --preset win --output-on-failure            # C/C++ tests
./build/win/bin/01_minimal_log.exe                # run a C example
```

Output: `build/win/bin/` (executables + DLLs), `build/win/lib/`. C# expects native libraries at `build/native/bin/` (Windows).

## Managed (.NET 10)

```bash
dotnet build
dotnet test KernelEngine.slnx
```

The solution is `KernelEngine.slnx`. Projects are flat under `src/csharp/`; examples under `examples/csharp/`; tests under `tests/csharp/`. See [05 - C# Layers](05%20-%20C%23%20Layers.md).

## Scripts

```bash
python scripts/compile_shaders.py    # compile all bgfx shaders to SPIR-V
python scripts/generate_bindings.py  # regenerate all C# P/Invoke bindings (ClangSharp)
python scripts/run_tests.py          # C/C++ + C# tests with coverage (gcovr + reportgenerator)
```

- **Shaders** compile to `src/cpp/render/bgfx/shaders/compiled/spirv/`. Shaderc lives in the vcpkg install tree (`build/win/vcpkg_installed/x64-windows/tools/bgfx/shaderc.exe`); platform `linux`, profile `spirv`.
- **Bindings** run `dotnet tool restore` from `src/csharp/` first, then process every `.rsp` under each project's `Native/` tree. **Never hand-edit generated bindings.**

## The stale-DLL trap ⚠️

Running `dotnet run --no-build` after a native C++ rebuild silently uses the previously-deployed `.dll` in `bin/Debug/net10.0/` — the native rebuild does **not** propagate. Symptom: you edited C++ but the example shows old behavior. Always `cmake --install` after a native build, and avoid `--no-build` after touching C++ (or run a fresh `dotnet build` so the latest native DLLs are copied). This has cost multiple debug cycles; a guard is tracked as Kanban `[B1.5]`.

## Conventions (summary)

- **C/C++**: `.h`/`.c` for C, `.hpp`/`.cpp` for C++. C is `snake_case` + `ke_` prefix; C++ is `PascalCase` (Google style). `#pragma once`. `clang-format` `BasedOnStyle: Microsoft`. No exceptions in C (return `ke_result`). `_params` suffix for parameter bags. Explicit `ke_allocator*` — no raw `malloc`.
- **C#**: XML doc comments on `public`/`protected` members. Generated bindings under `Native/Generated/` are never edited by hand.
- **Git**: Conventional Commits (`feat`/`fix`/`refactor`/`docs`/`test`/`chore`); one logical task per commit; stage files selectively (never `git add .`); single-line commit message, no multi-line body or `Co-Authored-By` footer.

## Documentation map

| Doc | Purpose |
|---|---|
| `docs/Reference/` (this) | What the engine is + will be, by domain |
| `docs/EngineRoadmap.md` | Product milestones M1–M5 + per-domain library choices |
| `docs/Kanban.md` | Active + pending work (cards) |
| `docs/Development/*` | Build, CI/CD, logging, versioning strategies + conventions |
| `docs/Reference/12 - Architecture Backlog & Decisions.md` | Defect catalog + design rationale + decisions log |
