# KernelEngine

A microkernel game engine: ABI-stable C contracts, Zig plugin backends behind them, and a managed C# layer for game code.

> **This file carries doctrine and conventions — never status.** What is built, what is in flight, and what is planned live in `docs/kanban/`, which is deliberately **not versioned** (see [`docs/conventions/docs.md`](docs/conventions/docs.md) for why). Any claim here about how the code behaves is checkable against the path it names; where the two disagree, the code wins and this file is the bug.

---

## Build

### Native (Zig + vcpkg manifest mode)

The root `build.zig` is the only native build orchestrator: it resolves vcpkg directly (manifest mode — `vcpkg.json` + `vcpkg-configuration.json`, no toolchain file), then invokes every plugin's own `build.zig` with one shared `--prefix` so every `.so`/`.dll` converges into one output directory. Each plugin still owns its own `build.zig`, callable standalone the same way (see any `src/zig/<plugin>/build.zig` header comment for its options).

vcpkg itself is fetched automatically (`build/tools/vcpkg-<version>/`) — no manual install, no `VCPKG_ROOT` needed. Pass `-Dvcpkg-root=<path>` (or export `VCPKG_ROOT`) only to point at an existing vcpkg checkout instead.

```bash
zig build --prefix build/native --cache-dir build/zig-cache       # configure + build + install, one step
zig build test --prefix build/native --cache-dir build/zig-cache  # every plugin's own Zig tests
build/native/bin/c_demo_01                                        # run a C example (c_demo_01.exe on Windows)
```

`--cache-dir` is not optional housekeeping: the root build gives every sub-build its own directory under it, `<cache-dir>/plugins/<name>`, so omitting it scatters one cache per plugin directory. The directories are separate on purpose: sub-builds sharing one cache serialize on its manifest lock, and a repeated build took 62 s against 3.7 s with one cache each. The `zig cc` wrappers in `vcpkg-triplets/` set `ZIG_LOCAL_CACHE_DIR` for the same reason — vcpkg's CMake runs them from the repo root, and `zig cc` caches into `$PWD/.zig-cache` unless told otherwise.

Build output converges entirely under the given `--prefix` (e.g. `build/native/{bin,lib}/`) — there is no separate install step. Everything the build fetches or produces stays under `build/`: `build/tools/` for fetched toolchains (vcpkg, slangc, wgpu-native), `build/vcpkg-installed/` for the ports, `build/zig-cache/` for one shared cache across the root build and every sub-build. Shared libraries land in `lib/` and executables in `bin/`; the C# side copies from `lib/` (`NativeTypeDir` in `src/csharp/NativeDependencies.targets`). Running an example or `dotnet test` also needs `build/native/lib` on `LD_LIBRARY_PATH` — the copy step brings each plugin along, but a plugin's transitive `libke_common.so` is resolved by the dynamic loader, which does not look in the output directory.

**Every native test is a Zig test living inside the implementation file it covers.** There is no C++ test suite; the two GTest binaries that predated the move to Zig are gone. A plugin declares its tests with `b.addTest` against its own source, run via `b.addRunArtifact` and hung off a `b.step("test", ...)` — see any `src/zig/<plugin>/build.zig`.

The root `test` step runs all of them. It cannot go stale: `Ctx.plugin` takes a required `.has_tests` / `.no_tests` argument, so a new plugin does not compile until that question is answered, and the test invocation reuses the same `-D` flag slice as the library build, so the two can never drift. Give a plugin a single test root that transitively imports its other files — a hand-written list of test roots lets a new test file go silently unrun, and lets two roots that import each other run the same test twice.

### Managed (.NET 10)

```bash
dotnet build
dotnet test KernelEngine.slnx
```

### Scripts

```bash
dotnet run scripts/compile_slang.cs   # compile a render-v2 .slang shader to WGSL (see root build.zig's Ctx.shader/materialShaders helpers for the driven build)
dotnet run scripts/generate_bindings.cs  # regenerate all C# P/Invoke bindings via ClangSharp
dotnet run scripts/regenerate_api.cs  # regenerate every kabic domain (ke_api.json + C# + C field tables) from scripts/api_domains.json
dotnet run scripts/coverage.cs        # C# test coverage report, C# only (clean | report subcommands)
```

Slang sources live with the pass that owns them (`src/zig/render/<pass>/shaders/`) plus the shared modules and authored materials under `src/shaders/`; they compile to WGSL into the build's shader-gen directory, and a pass loads them at runtime by logical name. `src/zig/render/service/shaders/` is the one exception — its single shader is embedded via `@embedFile`, because that has to exist before the module's own `zig build` starts. Binding regen runs `dotnet tool restore` from `src/csharp/` first, then processes every `.rsp` under a project's `Native/`.

**Known debt — no native/Zig coverage story.** `scripts/coverage.cs` only measures C#. Zig's own compiler has no source-coverage instrumentation. DWARF-based tools don't fill the gap either: `kcov` (which works via `libdw`, compiler-agnostic in principle) was tried directly against a Zig-compiled binary and produces silent 0% coverage — Zig 0.16 emits a line-table extended opcode `libdw` doesn't decode, confirmed by comparing against an identical `gcc`/`zig cc`-compiled C binary (which `kcov` measures correctly) and by inspecting the raw DWARF with `readelf --debug-dump=decodedline`. So the only native coverage signal is reading the tests, not measuring them.

### Running examples after a native rebuild

Never pass `--no-build` to `dotnet run` after a `zig build`. The native DLL copy step (a `PreserveNewest` item in `NativeDependencies.targets`) runs only during a build; `dotnet run --no-build` silently keeps the stale library already in `bin/Debug/net10.0/` and runs the old native code. Always use `dotnet run` / `dotnet build` (no `--no-build`); the timestamp-based copy then refreshes the native side automatically.

---

## Architecture — four layers

```
Layer 4 — C# managed          src/csharp/<domain>/KernelEngine.*/      game code, framework, wrappers
Layer 3 — C# bindings         src/csharp/<domain>/*/Native/Generated/  ClangSharp + kabic output
Layer 2 — plugins             src/zig/<domain>/<plugin>/               every implementation
Layer 1 — C contracts         src/c/<domain>/kernel_engine/<domain>/   ABI-stable vtables, headers only
```

**`src/c/` contains no implementation** — a domain's contract directory holds headers and nothing else; `src/c/window/` is exactly one file, `window.h`. **`src/zig/` contains no contract** — it holds implementations and, in each plugin's `include/`, only the factory header that creates them.

### Layer 1 — C contracts (`src/c/<domain>/`)

Pure C, ABI-stable (`extern "C"`). All public surface is vtable-shaped: a struct of function pointers, obtained from a factory. Seventeen domains: `asset`, `audio`, `configuration`, `ecs`, `framework`, `input`, `logger`, `math`, `physics`, `render`, `resource_cache`, `runtime`, `scheduler`, `spatial`, `text`, `view`, `window`.

One `-I src/c/<domain>` per domain, so a consumer only ever sees the domains it asked for — want `scheduler`? include `scheduler`. There is no meta-target and no umbrella header; consumers link the specific plugin `.so`s they use (`ke_logger_simple`, `ke_resource_cache_default`, …).

Contracts worth knowing by name:
- `ke_logger` / `ke_logger_sink` — pluggable logging
- `ke_ecs` — entity lifetime + component storage + query, language-agnostic
- `ke_runtime` — phase loop, parallel waves, defer queue, fixed timestep
- `ke_system_ctx` — the only doorway to component memory inside a system body; `ke_ecs_commands` — the queue its structural changes are recorded into
- `ke_scheduler` — the single shared worker pool every parallel subsystem routes through
- `ke_render` / `ke_window` — renderer and window backends
- `ke_resource_cache` — refcount + path-keyed dedup

### Layer 2 — Plugins (`src/zig/<domain>/<plugin>/`)

Implemented in Zig, behind the C ABI. Each plugin is a shared library that exports **exactly one symbol per factory header** — the create function. Everything else it exposes is a vtable returned by that factory. Thirty-one plugins are declared in the root `build.zig`; `grep 'ctx.plugin("' build.zig` is the authoritative list, since a plugin that is not declared there is not built.

No C++ implementation. The one `.cpp` in the tree, `src/zig/common/test/cpp_static_init_probe.cpp`, is a test fixture for the Windows DLL start-up workaround. The C libraries plugins compile (stb, miniaudio) come from vcpkg; tomlc99 is the one vendored library.

Vendoring rule: when vcpkg lacks a pure-C library, vendor it inside `<plugin>/third_party/<lib>/` with a `VENDOR.md` recording upstream, license and sync date. Contained — never leaks to a sibling plugin.

#### Layer boundary rule (non-negotiable)

- `src/c/` is the **sole** source of public engine API. Every interface, vtable, struct and enum the engine exposes lives there. C ABI only.
- A plugin exposes exactly **one factory per factory header**, under `<plugin>/include/kernel_engine/<domain>/[<plugin>/]<name>.h`. Everything else is implementation detail under `<plugin>/src/`.
- Contract headers declare vtable shapes **only** — no `KE_*_API` export macros, no plain function declarations. Exports live exclusively in the factory headers.
- If a "generic utility" wants to live in a plugin's public header, it belongs in a contract directory instead.

### Layer 3 — C# bindings

Generated P/Invoke, one `Native/` directory per managed project (28 of them), each driven by its own `.rsp`. **Never edit `Generated/` by hand** — regenerate with `dotnet run scripts/generate_bindings.cs`.

Two generators feed this layer and they are not interchangeable: **ClangSharp** produces the raw struct/function surface, and **kabic** (`src/csharp/kabic/`) produces the idiomatic projection from the same headers' doc tags, driven by `scripts/api_domains.json`. Ten `scripts/check_*.cs` gates keep both honest against the headers.

### Layer 4 — C# managed (`src/csharp/<domain>/`)

Thin wrappers expose the native vtables as managed types. Game code talks to these, and composes them by dependency injection from its own `Program.cs`:

```csharp
var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<INativeEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(800, 600, "Title"));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();
runtime.LoadModules(sp);

while (!window.ShouldClose()) runtime.Tick(dt);
```

Game code becomes a runtime module too, registering its own components and systems via `IRuntimeModule.OnLoad`. The smallest working host is [`examples/csharp/00_runtime_minimal/Program.cs`](examples/csharp/00_runtime_minimal/Program.cs) — copy that, not this snippet.

A service locator is forbidden: injection happens in the orchestration area, never by asking a container for a dependency from inside engine code.

---

## Threading model

There is one worker pool, behind `ke_scheduler`, and workers are addressed by index, never by name: no contract or plugin defines a "sim" or a "render" thread. A system body runs on whichever worker takes it unless it asks to be pinned to an index. What runs where is in [`docs/architecture/threading.md`](docs/architecture/threading.md); read the pinning there before assuming any thread affinity.

**Sim ↔ render boundary**: the mechanism is `runtimeTick` in `src/zig/runtime/src/runtime.zig`. Read it there. Do not trust a prose description of it — not this file's, not any document's. Any design decision that turns on how sim and render are decoupled must cite that source, because this paragraph cannot stay true on its own.

**Worker pool**: a single shared `ke_scheduler` (enkiTS). The runtime's wave dispatcher submits tasks directly, and every parallel subsystem routes through the same pool. The flecs plugin asks flecs for no threads (`ecs_init()` only).

---

## Coding conventions

### C (contracts) and Zig (implementations)
- **Extensions**: `.h` for contract and factory headers; `.zig` for implementations. C++ is not used — do not introduce `.cpp`/`.hpp`.
- **Naming**: `snake_case` with a `ke_` prefix on everything crossing the ABI.
- **Headers**: `#pragma once` always. Public API in a contract directory or a plugin's `include/`; nothing under `src/` is includable from outside the plugin.
- **Error handling**: a call that can fail takes `ke_error **out_error` and, on failure, fills it with `KE_ERROR_SET` and returns its failure sentinel (`false`, a null handle, an invalid id). All callers check the return.
- **Memory**: each plugin owns its allocation, and the factory functions do **not** take an allocator parameter. Raw pointers are non-owning unless documented otherwise.
- **Param structs**: standardize on `_params` suffix for parameter bags (construction, registration, etc.). Never `_desc`, `_descriptor`, `_info`, or `_config`.
- **No `impl_` / `Impl` / `_impl` naming**: vtable function-pointer slots use `<plugin>_<verb>`; state structs use `XxxState`; filenames are plain. Pattern grew by inertia and is rejected in new code.

### C#
- XML doc comments (`///`) on all `public` and `protected` members.
- Generated bindings in `Generated/` — never edit manually.
- `InternalsVisibleTo` is **banned**. A native handle crosses assemblies through the public `Native` pointer of a generated `INative<Domain>` interface, implemented explicitly so the object itself exposes only managed methods — never through `internal` plus a friend list.

### Git / commits
- Conventional Commits: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.
- One commit per logical task. Stage files selectively — never `git add .`.
- Commit messages are a single line. No multi-line body. No `Co-Authored-By` footer.

---

## Project rules

1. **Plugins implement vtables; contract headers declare them, factory headers create them, period.** No plain exported functions in plugin contract headers. The plugin's symbol surface to the rest of the engine is the factory function and the vtable methods it returns. Kernel built-ins are the only header path allowed to export plain symbols.

2. **No `InternalsVisibleTo`.** See above. Use public `Native` pointers.

3. **Search precedents before inventing — but judge the precedent first.** The project is mature enough that almost every structural decision has an existing example. Before designing a new plugin layout, a new binding `.rsp`, a new plugin `build.zig`, a new vtable split — find the closest existing case in the repo. Match the established pattern; if it's genuinely wrong, propose changing the pattern explicitly rather than diverging in parallel.
   - **Frequency is not endorsement.** A shape repeated across a hundred files is a precedent only if it was *decided*. Most of what exists here was written before the convention that now governs it, and the plan is deliberate: settle a convention, write all new code to it, and refactor the old separately — so that "old" shrinks instead of reproducing. Citing the old code as license to keep writing it defeats the entire plan.
   - **These are never precedents**, no matter how many times they appear: a workaround, a gambiarra, dirty code, coupling, a shortcut, local convenience, and anything a rule in this file already forbids (comments in source, `assert`/`abort`, `InternalsVisibleTo`, magic numbers, C++ tests). Finding one means you found **debt**, not a pattern — name it, don't extend it.
   - **The test is "was this chosen, and is it still what we'd choose?"**, not "does this already exist?". If the answer is no, the rule that forbids it wins over the precedent that shows it. If you can't tell, that is a question for the PO, not a licence to copy.

4. **Consult legacy before rewriting.** When porting a concept off legacy code into a new framework/runtime, read the legacy implementation first, then design the replacement consciously. Refazer (rewriting from scratch) is sometimes correct; refazer-blind (without consulting what was there) is never correct. Legacy code carries hard-won lessons (edge cases, conventions, lifecycle hooks); skipping it means re-discovering them as regressions.

5. **No mutex / condvar / raw thread in plugins.** The scheduler is the synchronization layer. Async completion uses `ke_scheduler`'s submit-to-thread plus its wait. Producer-consumer ordering uses phase boundaries (register producer in phase N, consumer in phase N+1; the runtime guarantees the barrier). The legacy `ke_resource_queue` that reinvented a Future on `std::mutex` + `condition_variable` was deleted in C-phase 4.5 of the runtime arc.

6. **`assert()` and `abort()` are banned everywhere in engine code.** The engine has `ke_error` — a robust, typed, thread-local error propagation system. Any condition that would be expressed as `assert(x)` must instead be expressed as a `KE_ERROR_SET` plus the call's failure sentinel. Any path that would call `abort()` must translate to a `ke_error` and return to the caller. This includes internal defensive guards and plugin boundaries. Delegating failure to the OS abort dialog when a proper error system exists is a hard violation.

7. **The framework is a plugin like any other**, at `src/zig/framework/`, with its vtable contracts in `src/c/framework/` and reached only through them and its factory headers (`world_create.h`, `scene_tree_create.h`, `scene_loader_create.h`, `script_host_create.h`, `signal_bus_create.h`, `asset_resolver_create.h`, `input_actions_create.h`). Being opinionated about vocabulary does not buy it a privileged path past the ABI: a dynamic-language binding must be able to reach the framework the same way it reaches the renderer.

8. **No magic numbers — we are engine developers, not game developers.** A numeric constant is only allowed to stay a bare `const` when it is truly non-dynamic — implied by the algorithm itself, with no other value that would ever make sense (a 4x4 matrix, a quaternion's 4 components). Every other constant is a **game-tuning or workload-shape value**, and imposing it on the caller as a hardcoded ceiling is not our call to make. It must be a constructor parameter or params-struct field, with the current value kept only as the default for convenience. This applies especially to anything found to be a real limiting factor — a buffer size, a per-bucket cap, a grid resolution — where exceeding it produces a hard failure or visible artifact instead of graceful degradation. Stress tests exist to discover a *sane default*, not to justify a hardcoded ceiling; once a constant is shown to be limiting, promote it to a field rather than tuning the number in place. Don't flood constructors with parameters nobody sets — only promote what's actually been shown to matter.

9. **The narrow, clean path always beats the wide, dirty one — and it pays back later, not immediately.** This project does not choose an architecture because it is easy today; it chooses the one that is *correct* even when the harder path costs more up front. The Zig migration (rewriting the native build orchestration end to end, unifying every plugin under one build system and one target-triplet model) and the vtable-shaped C ABI headers were both expensive to do — and both are exactly why `kabic` could generate a real multi-language compiler pipeline on top of them without a second redesign, and why a future console port's cross-compilation story collapses to "one toolchain description, reused by every C/C++ codebase this project depends on" instead of N bespoke ones. Optimizing for what is easy to ship this week is what produces the workarounds this doctrine exists to prevent.
   - A one-off workaround to unblock a local, narrow problem is fine and expected — not everything is a referendum on the architecture.
   - But **never stay attached to the existing architecture out of sunk cost.** If a design is shown to be wrong, refactor it — all the way, including a full rewrite, if that is what correctness requires. This project has already done that once — the entire native side was rewritten from CMake and C++ to Zig — and treats it as a normal, available tool, not a last resort.
   - When evaluating a new idea, the question is never "do we need this yet" (see rule 8's YAGNI note, which this generalizes) — it is "is this the right shape," independent of how much existing code would need to change to get there.

---

## Key documents

Every document that mixed a contract with a moment was retired; `git log -- docs/` reaches all of
them, and they are not a source for anything. What `docs/` holds is listed in
[`docs/README.md`](docs/README.md), and the rules every one of them is written to are in
[`docs/conventions/docs.md`](docs/conventions/docs.md).

Where to look when this file is not enough:

| question | where the answer actually is |
|---|---|
| what does a contract require? | the header in `src/c/<domain>/` — it is the API, not a description of one |
| how does sim hand off to render? | `src/zig/runtime/src/runtime.zig` |
| which plugins exist? | `grep 'ctx.plugin("' build.zig` |
| what does a generated projection look like, and why? | `src/csharp/kabic/`, plus the `scripts/check_*.cs` gate that pins it |
| what is being worked on? | `docs/kanban/` — unversioned, and the only place status is allowed |
