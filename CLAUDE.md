# KernelEngine

A microkernel game engine: ABI-stable C contracts, Zig plugin backends behind them, and a managed C# layer for game code.

> **This file carries doctrine and conventions — never status.** What is built, what is in flight, and what is planned live in `docs/kanban/`, which is deliberately **not versioned** (see [`docs/conventions/docs.md`](docs/conventions/docs.md) for why). Any claim here about how the code behaves is checkable against the path it names; where the two disagree, the code wins and this file is the bug.

---

## Build

### Native (Zig + vcpkg manifest mode)

The root `build.zig` is the only native build orchestrator: it resolves vcpkg directly (manifest mode — `vcpkg.json` + `vcpkg-configuration.json`, no toolchain file), then builds every plugin in its own graph: each one is a path dependency in the root `build.zig.zon`, and the root installs every `.so`/`.dll` into one output directory. Each plugin still owns its own `build.zig`, callable standalone with the same options (see any `src/zig/<plugin>/build.zig` header comment for its options).

vcpkg itself is fetched automatically (`build/tools/vcpkg-<version>/`) — no manual install, no `VCPKG_ROOT` needed. Pass `-Dvcpkg-root=<path>` (or export `VCPKG_ROOT`) only to point at an existing vcpkg checkout instead.

```bash
zig build --prefix build/native --global-cache-dir build/zig-global       # configure + build + install, one step
zig build test --prefix build/native --global-cache-dir build/zig-global  # every plugin's own Zig tests
zig build docs --prefix build/native --global-cache-dir build/zig-global  # build/native/docs/{engine,kabic}/, pages generated from the sources
build/native/bin/c_demo_01                                        # run a C example (c_demo_01.exe on Windows)
build/native/bin/docir query <name> src                           # what the sources document about a symbol, a file or an idea
```

`docir` is installed by the build beside the examples, at the version pinned in `build.zig.zon`. It answers from the doc comments of the sources each time it is asked, so nothing has to be generated first; `.claude/skills/docir/SKILL.md` says how to ask.

`--global-cache-dir` is not optional housekeeping: without it Zig caches into the user's home. The local cache is `.zig-cache` at the repository root, where Zig puts it by default; the root build gives `vcpkg install` both through `ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR`, because vcpkg's CMake runs `zig cc` from directories of its own.

Build output converges entirely under the given `--prefix` (e.g. `build/native/{bin,lib}/`) — there is no separate install step. Everything the build fetches or produces stays under `build/`: `build/tools/` for fetched toolchains (vcpkg, slangc, wgpu-native, RenderDoc), `build/vcpkg-installed/` for the ports, `build/vcpkg-archives/` and `build/vcpkg-registries/` for vcpkg's compiled-port archives and registry checkouts, `build/zig-global/` for Zig's global cache, and `build/nuget/` for the NuGet packages (`nuget.config` at the root points there). The two exceptions are at the repository root and ignored by git: `.zig-cache/`, the local cache of Zig, and `zig-pkg/`, where Zig unpacks the packages declared by URL in a `build.zig.zon` (zmath, docir). Shared libraries land in `lib/` and executables in `bin/`; the C# side copies from `lib/` (`NativeTypeDir` in `src/csharp/NativeDependencies.targets`). Every plugin links `ke_common` with an `$ORIGIN` runpath, so a plugin copied beside it finds it; running an example or `dotnet test` needs no `LD_LIBRARY_PATH`.

**Every native test is a Zig test living inside the implementation file it covers.** There is no C++ test suite; the two GTest binaries that predated the move to Zig are gone. A plugin declares its tests with `b.addTest` against its own source, run via `b.addRunArtifact` and hung off a `b.step("test", ...)` — see any `src/zig/<plugin>/build.zig`.

The root `test` step runs all of them. It cannot go stale: `Ctx.member` takes a required `.has_tests` / `.no_tests` argument, so a new plugin does not compile until that question is answered, and the plugin's tests are configured by the same `b.dependency` call as its library, so the two can never drift. Give a plugin a single test root that transitively imports its other files — a hand-written list of test roots lets a new test file go silently unrun, and lets two roots that import each other run the same test twice.

### Managed (.NET 10)

```bash
dotnet build
dotnet test KernelEngine.slnx
```

### Scripts

```bash
dotnet run scripts/compile_slang.cs   # compile a render-v2 .slang shader to WGSL (see root build.zig's Ctx.shader/materialShaders helpers for the driven build)
dotnet run --project src/csharp/kabic/Kabic.Cli -- bindings  # regenerate all C# P/Invoke bindings via ClangSharp, configured from the manifest "bindings" array and the headers
dotnet run --project src/csharp/kabic/Kabic.Cli -- generate  # regenerate every kabic domain (ke_api.json + C# + C field tables) from scripts/api_domains.json
dotnet run scripts/coverage.cs        # C# test coverage report, C# only (clean | report subcommands)
dotnet run scripts/verify.cs -- docs  # generate the reference pages and build the documentation site into build/docs-site (DocFX, pinned in .config/dotnet-tools.json)
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

Implemented in Zig, behind the C ABI. Each plugin is a shared library that exports **exactly one symbol per factory header** — the create function. Everything else it exposes is a vtable returned by that factory. Thirty-three plugins are declared in the root `build.zig`; `grep 'ctx.member("' build.zig` is the authoritative list, since a plugin that is not declared there is not built.

No C++ implementation. The one `.cpp` in the tree, `src/zig/common/test/cpp_static_init_probe.cpp`, is a test fixture for the Windows DLL start-up workaround. The C libraries plugins compile (stb, miniaudio) come from vcpkg; tomlc99 is the one vendored library.

Dependencies enter through dependency management: vcpkg for native libraries, NuGet for .NET, `build.zig.zon` for Zig packages and C sources built by the graph. A pinned fetch step in the root `build.zig` is the exception for what none of them carries, a vendored copy the exception after that, and the machine's environment or the operating system's package manager is never a source — see [`docs/conventions/build.md`](docs/conventions/build.md).

Vendoring rule: when no package manager carries a pure-C library and it cannot be fetched, vendor it inside `<plugin>/third_party/<lib>/` with a `VENDOR.md` recording upstream, license and sync date. Contained — never leaks to a sibling plugin.

#### Layer boundary rule (non-negotiable)

- `src/c/` is the **sole** source of public engine API. Every interface, vtable, struct and enum the engine exposes lives there. C ABI only.
- A plugin exposes exactly **one factory per factory header**, under `<plugin>/include/kernel_engine/<domain>/[<plugin>/]<name>.h`. Everything else is implementation detail under `<plugin>/src/`.
- Contract headers declare vtable shapes **only** — no `KE_*_API` export macros, no plain function declarations. Exports live exclusively in the factory headers.
- If a "generic utility" wants to live in a plugin's public header, it belongs in a contract directory instead.

### Layer 3 — C# bindings

Generated P/Invoke, one `Native/` directory per managed project (28 of them), each configured from the `bindings` array of `scripts/api_domains.json`. **Never edit `Generated/` by hand** — `kabic bindings` derives the ClangSharp configuration from the manifest and the headers and writes it.

Two generators feed this layer and they are not interchangeable: **ClangSharp** produces the raw struct/function surface, and **kabic** (`src/csharp/kabic/`) produces the idiomatic projection from the same headers' doc tags, driven by `scripts/api_domains.json`. Nine gates, five `kabic check` commands and four of the `scripts/check_*.cs`, keep both honest against the headers.

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

There is one worker pool, behind `ke_scheduler`, and workers are addressed by index, never by name: no contract or plugin defines a "sim" or a "render" thread. A system body runs on whichever worker takes it; nothing pins a system or a task to a worker, and an order between systems is stated as component access. What runs where is in [`docs/architecture/threading.md`](docs/architecture/threading.md).

**Sim ↔ render boundary**: the mechanism is `runtimeTick` in `src/zig/runtime/src/runtime.zig`. Read it there. Do not trust a prose description of it — not this file's, not any document's. Any design decision that turns on how sim and render are decoupled must cite that source, because this paragraph cannot stay true on its own.

**Worker pool**: a single shared `ke_scheduler` (enkiTS). The runtime's wave dispatcher submits tasks directly, and every parallel subsystem routes through the same pool. The flecs plugin asks flecs for no threads (`ecs_init()` only).

---

## Coding conventions

### Comments
- No comments in any file: source, scripts, workflows, shaders, build files. The code and its names carry the meaning.
- The exception is documentation the build generates pages from. A doc comment on a declaration (`///` in Zig, `///` and `<summary>` in C#, Doxygen in C headers) states what a caller relies on: what it passes, what it gets back, what fails. In a contract it is required on every public declaration. In an implementation file it is required on a function that implements a slot of a contract and on a type that holds state, where it states the part the declaration plays in the mechanism, never a retelling of its body; any other function carries one only for a precondition or an invariant its body does not show, and a field, an enum value or a test helper carries none. A file doc comment at the top of an implementation file (`//!` in Zig, `@file` in C) is a summary of one to three sentences saying what the file answers for. C# has no file doc comment: the `<summary>` of the type says it.
- An example under `examples/` may also carry the marker that delimits a passage a guide quotes: `#region` in C#, a marker comment in Zig and C. The marker names the passage and says nothing else.
- Rationale, history, a consumer's or example's name, `<remarks>`, `<para>`, `@note`, `TODO` and any line of context are comments, however they are formatted. The rules a doc comment is written to are in [`docs/conventions/docs.md`](docs/conventions/docs.md).

### C (contracts) and Zig (implementations)
- **Extensions**: `.h` for contract and factory headers; `.zig` for implementations. C++ is not used — do not introduce `.cpp`/`.hpp`.
- **Naming**: `snake_case` with a `ke_` prefix on everything crossing the ABI.
- **Headers**: an `#ifndef` include guard named after the path, `KERNEL_ENGINE_<DOMAIN>_<NAME>_H_`. Public API in a contract directory or a plugin's `include/`; nothing under `src/` is includable from outside the plugin.
- **Error handling**: a call that can fail takes `ke_error **out_error` and, on failure, fills it with `KE_ERROR_SET` and returns its failure sentinel (`false`, a null handle, an invalid id). All callers check the return.
- **Memory**: each plugin owns its allocation, and the factory functions do **not** take an allocator parameter. Raw pointers are non-owning unless documented otherwise.
- **Param structs**: standardize on `_params` suffix for parameter bags (construction, registration, etc.). Never `_desc`, `_descriptor`, `_info`, or `_config`.
- **Shape of a plugin**, where the language is silent:
  - The entry file is named after the domain and the plugin; a render pass ends in `module`.
  - The state is a struct named `State`, embedding the vtable as the field `api`, whose handle points back at it; one function named `stateOf` recovers it from a slot's first argument.
  - A slot function is a camelCase verb named after its slot, prefixed only in a file that implements several vtables. No `impl_`, `Impl` or `_impl` in a name.
  - A slot refuses a null first argument: silently without a result, as an invalid argument with one. A slot with an error lane fills it on every failure.
  - A factory is `export` without `pub`, takes a params struct in which zero selects the default, and on failure frees what it took and returns the zeroed handle.
  - C types reach a plugin through one file of imports; shared Zig source by module name.
  - A test is named by a sentence stating the behaviour, uses the shared stubs, and the last test of a plugin checks that nothing leaked.
  - A managed module is named in PascalCase with no dot; a command line tool exits 0, 1 on a failure, 2 when it could not run.

### C#
- XML doc comments (`///`) on all `public` and `protected` members, carrying the API contract only (see Comments).
- Generated bindings in `Generated/` — never edit manually.
- `InternalsVisibleTo` is **banned**. A native handle crosses assemblies through the public `Native` pointer of a generated `INative<Domain>` interface, implemented explicitly so the object itself exposes only managed methods — never through `internal` plus a friend list.

### Git / commits
- Conventional Commits: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.
- One commit per logical task. Stage files selectively — never `git add .`.
- A commit message follows the Conventional Commits 1.0.0 specification; a breaking change carries `!` and a `BREAKING CHANGE:` footer. No `Co-Authored-By` footer.
- `main` takes commits after `scripts/ci_local.cs` passes on it; work of several commits goes through a branch and a `--no-ff` merge. See [`docs/conventions/git.md`](docs/conventions/git.md).

---

## Project rules

The rules below and the conventions above that a machine can check are checked by `scripts/check_engine_rules.cs`, which `scripts/verify.cs` runs with the other gates. Where a rule is already broken it holds a ceiling that can only go down.

1. **A plugin exposes vtables behind one factory per header.** A contract header declares vtable shapes only; a plugin exports one create function per factory header; only the shared kernel library exports plain functions.

2. **No `InternalsVisibleTo`.** A native handle crosses assemblies through the `Native` pointer of a generated `INative<Domain>` interface.

3. **Search precedents before inventing — but judge the precedent first.** The project is mature enough that almost every structural decision has an existing example. Before designing a new plugin layout, a new binding `.rsp`, a new plugin `build.zig`, a new vtable split — find the closest existing case in the repo. Match the established pattern; if it's genuinely wrong, propose changing the pattern explicitly rather than diverging in parallel.
   - **Frequency is not endorsement.** A shape repeated across a hundred files is a precedent only if it was *decided*. Most of what exists here was written before the convention that now governs it, and the plan is deliberate: settle a convention, write all new code to it, and refactor the old separately — so that "old" shrinks instead of reproducing. Citing the old code as license to keep writing it defeats the entire plan.
   - **These are never precedents**, no matter how many times they appear: a workaround, a gambiarra, dirty code, coupling, a shortcut, local convenience, and anything a rule in this file already forbids (comments in source, `assert`/`abort`, `InternalsVisibleTo`, magic numbers, C++ tests). Finding one means you found **debt**, not a pattern — name it, don't extend it.
   - **The test is "was this chosen, and is it still what we'd choose?"**, not "does this already exist?". If the answer is no, the rule that forbids it wins over the precedent that shows it. If you can't tell, that is a question for the PO, not a licence to copy.

4. **Consult legacy before rewriting.** When porting a concept off legacy code into a new framework/runtime, read the legacy implementation first, then design the replacement consciously. Refazer (rewriting from scratch) is sometimes correct; refazer-blind (without consulting what was there) is never correct. Legacy code carries hard-won lessons (edge cases, conventions, lifecycle hooks); skipping it means re-discovering them as regressions.

5. **No mutex, condition variable or raw thread in a plugin.** The scheduler is the synchronisation layer: work is dispatched to `ke_scheduler` and waited on through it, and a producer and a consumer are ordered by phases.

6. **No `assert` and no `abort` in engine code.** Every failure, an internal guard included, fills a `ke_error` and returns the failure sentinel of the call.

7. **The framework is a plugin like any other**, at `src/zig/framework/`, reached only through its contracts in `src/c/framework/` and its factory headers.

8. **No magic numbers.** A number stays a bare constant only when the algorithm implies it; any other is a field of a params struct or an argument of the factory, with the current value as the default. Only what was shown to matter is promoted.

9. **The correct shape beats the easy one.** An idea is judged by whether it is the right shape, never by how much existing code would change; a design shown to be wrong is refactored all the way. A local workaround for a narrow problem is allowed and named as one.

---

## Key documents

`docs/` holds contracts and mechanisms, and nothing else; what it holds is listed in
[`docs/README.md`](docs/README.md), and the rules every one of its documents is written to are in
[`docs/conventions/docs.md`](docs/conventions/docs.md). Anything that describes a moment lives in the
unversioned kanban.

Where to look when this file is not enough:

| question | where the answer actually is |
|---|---|
| what does a contract require? | the header in `src/c/<domain>/` — it is the API, not a description of one |
| what is this symbol or file for, and where is an idea explained? | `build/native/bin/docir query <name> src`, then the code at the location it gives |
| how does sim hand off to render? | `src/zig/runtime/src/runtime.zig` |
| which plugins exist? | `grep 'ctx.member("' build.zig` |
| what does a generated projection look like, and why? | `src/csharp/kabic/`, plus the `scripts/check_*.cs` gate that pins it |
| what is being worked on? | `docs/kanban/` — unversioned, and the only place status is allowed |
