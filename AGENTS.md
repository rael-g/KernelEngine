# KernelEngine

A microkernel game engine: ABI-stable C contracts, Zig plugins that implement them, and a managed C# layer
for game code. This file holds the doctrine and the conventions every change is written to. Every claim it
makes about the code names the path that proves it; where the two disagree, the code wins and this file is
the bug.

## Where to look

| question | where the answer is |
|---|---|
| what does a contract require? | its header under `src/c/<domain>/`: the header is the API |
| what is a symbol or a file for? | `build/native/bin/docir query <name> src`, then the code at the location it gives |
| which plugins exist? | `grep 'ctx.member("' build.zig`: a plugin not declared there is not built |
| how does sim hand off to render? | `src/zig/extraction/default/src/extraction_default.zig`, read there and never from prose |
| what does a generated projection look like? | the kabic submodule (`external/kabic`) and the `scripts/check_*.cs` gate that pins it |
| how is a document written? | [`docs/conventions/docs.md`](docs/conventions/docs.md) |
| how does work reach `main`? | [`docs/conventions/git.md`](docs/conventions/git.md) and [`docs/conventions/ci.md`](docs/conventions/ci.md) |

## Build and test

```bash
zig build --prefix build/native --global-cache-dir build/zig-global       # vcpkg ports, every plugin, the tools
zig build test --prefix build/native --global-cache-dir build/zig-global  # every plugin's Zig tests
zig build docs --prefix build/native --global-cache-dir build/zig-global  # reference pages from the sources
zig build coverage -Dcoverage --prefix build/native --global-cache-dir build/zig-global  # Zig test coverage, Linux
dotnet build
dotnet test KernelEngine.slnx
dotnet run scripts/verify.cs              # every stage the CI runs; name one to run it alone (build, gates, docs, ...)
dotnet run scripts/ci_local.cs            # verify.cs in a fresh clone inside the CI image; --windows for the Windows target
```

- The root `build.zig` is the only native orchestrator. It fetches vcpkg itself (manifest mode, no
  `VCPKG_ROOT`) and builds each plugin as a path dependency declared in `build.zig.zon`. Each plugin's own
  `build.zig` is a description handed to `ke_build.plugin` (`src/zig/build/build.zig`) and builds standalone.
- `--global-cache-dir` is required; without it Zig caches into the home directory. Everything fetched or
  produced lands under `build/`, except `.zig-cache/` and `zig-pkg/` at the root.
- Libraries land in `build/native/lib/`, executables in `build/native/bin/`. A plugin that links another
  carries an `$ORIGIN` runpath, so nothing needs `LD_LIBRARY_PATH`.
- Never `dotnet run --no-build` after a native rebuild: the native libraries are copied into the C# output
  only during a build (`src/csharp/NativeDependencies.targets`), so `--no-build` runs the old native code.
- Bindings and projections are generated, never edited:
  `dotnet run --project external/kabic/src/Kabic -- --cache-dir build/kabic-cache bindings` regenerates the
  P/Invoke layer, `generate` every kabic domain from `scripts/api_domains.json`, with no extension of the
  engine's.
- Slang shaders live with the pass that owns them (`src/zig/render/<pass>/shaders/`), shared modules and
  materials under `src/shaders/`; they compile to WGSL and are loaded at runtime by logical name.
- Coverage: `zig build coverage -Dcoverage` runs every plugin's tests under kcov, fetched by
  `build.zig.zon` and built for musl, compiling them with LLVM, whose line table kcov reads; the merged
  report lands in `<prefix>/coverage`. `dotnet run scripts/coverage.cs` measures the C# and the Zig and
  prints both as tables, per module; `-- report` prints them again.

## Tests

- Every native test is a Zig test inside the implementation file it covers, declared by the plugin's
  `build.zig`. There is no C++ test suite.
- A plugin has unit tests only: every contract it depends on is a substitute (zsub) configured in the
  test, and it never reads the machine's files or runs another plugin. A test that composes real
  implementations is an integration test, written in the language whose surface it exercises.
- A plugin has one test root that imports its other files. `Ctx.member` takes a required `.has_tests` or
  `.no_tests`, so a new plugin cannot skip the question.
- No test needs a human eye. A feature or a game lands with its tests.

## Architecture

```
Layer 4  C# managed    src/csharp/<domain>/KernelEngine.*/        game code, framework, wrappers
Layer 3  C# bindings   src/csharp/<domain>/*/Native/Generated/    ClangSharp and kabic output
Layer 2  plugins       src/zig/<domain>/<plugin>/                 every implementation
Layer 1  contracts     src/c/<domain>/kernel_engine/<domain>/     ABI-stable vtables, headers only
```

**Contracts.** `src/c/` holds headers and nothing else, and is the sole source of public engine API: C ABI,
every surface a struct of function pointers obtained from a factory. Each domain is its own include path,
so a consumer sees only the domains it asks for; there is no umbrella header.

**Plugins.** `src/zig/` holds implementations and no contract. A plugin is a shared library exporting one
create function per factory header (`<plugin>/include/kernel_engine/<domain>/...`) and one log-callback
setter; everything else is a vtable that factory returns. It logs with `std.log`, the host sets where each
library's log goes, and the host injects every dependency. Contract types reach a plugin through the ABI
packages kabic generates (`src/zig/abi/<domain>/`).

**Bindings.** One `Native/` directory per managed project, configured from the `bindings` array of
`scripts/api_domains.json`. ClangSharp produces the raw surface; kabic produces the idiomatic projection
from the headers' doc tags. kabic's generic output is the default: accept it if it is enough, otherwise ask
whether the concept belongs in kabic's core, and only a concept that is neither goes to an extension.

**Managed.** Each factory is a class wrapping its vtable. Game code starts from `KernelEngine.Sdk` and
`KernelEngine.Sdk.Defaults` (`src/csharp/sdk/`); a complete game is
[`examples/csharp/games/pong/`](examples/csharp/games/pong/Program.cs). No service locator: a container in
the host is composition, and each plugin still receives its dependencies through its factory.

**Dependencies** enter through vcpkg, NuGet or `build.zig.zon`; then a pinned fetch step in the root
`build.zig`; then, for a pure-C library nothing carries, a vendored copy in `<plugin>/third_party/<lib>/`
with a `VENDOR.md` (upstream, license, sync date), never shared with a sibling. The machine's environment is
never a source. See [`docs/conventions/build.md`](docs/conventions/build.md).

## Threading

Every thread belongs to one of three parts the host creates: the job system (`ke_job_system`) runs the
frame, the async system (`ke_async`) runs CPU work that spans frames, and an I/O implementation (`ke_io`)
runs its own mechanism. Each starts its threads from a ceiling its settings fix; nothing else starts one,
and a library a plugin wraps is configured not to (the flecs plugin calls `ecs_init()` only). Only the job
system is sized to the cores. Work on the job or async system never blocks on I/O. A completion is waited
on only where its contract allows; elsewhere it is a dependency, and a read during a frame answers
`KE_RESULT_PENDING`. Workers are addressed by index, nothing is pinned to one, and an order between systems
is stated as component access. What runs where: [`docs/architecture/threading.md`](docs/architecture/threading.md).

## Conventions

### Comments

No comments in any file: source, scripts, workflows, shaders, build files. The exception is the doc comment
the build generates pages from (`///` and `//!` in Zig, `///`/`<summary>` in C#, Doxygen in C headers):

- In a contract, every public declaration carries one, stating what a caller passes, gets and can fail with.
- In an implementation, a slot function and a state type carry one, stating the part it plays; any other
  function only for a precondition or invariant its body does not show. Fields, enum values and test
  helpers carry none. An implementation file opens with a one-to-three sentence `//!` (or `@file`) summary.
- Rationale, history, `<remarks>`, `@note` and `TODO` are comments, however formatted.
- An example may mark a passage a guide quotes (`#region`, or a marker comment) with its name only.

The full rules are in [`docs/conventions/docs.md`](docs/conventions/docs.md).

### C and Zig

- `snake_case` with a `ke_` prefix on everything crossing the ABI; `.h` headers guarded by
  `KERNEL_ENGINE_<DOMAIN>_<NAME>_H_`. Contract headers declare vtable shapes only: no export macros, no
  plain functions.
- A call that can fail returns `ke_result`, writes its value through a last `out_` parameter, and logs the
  reason with `log.warn`. Callers check it.
- Each plugin owns its allocation; factories take no allocator. Raw pointers are non-owning unless stated.
- A struct as an argument is justified by reuse or by describing an object; a descriptor of something to
  create or register is suffixed `_desc`. Everything else is positional.
- A factory takes its dependencies, then what the host computes, then a `ke_settings *` with what a person
  writes in the project file, read once. A value that changes afterwards is a slot, never a setting. A key
  every implementation reads is a `KE_<DOMAIN>_SETTING_*` macro in the contract; the implementation
  publishes defaults and ranges through `settings_schema` (`src/zig/settings/schema/`) and refuses an
  unknown key, a wrong type or an out-of-range value. Zero is a value, never "use the default".
- Shape of a plugin: the entry file is named after domain and plugin (a render pass ends in `module`); the
  state is `State`, embedding the vtable as `api`, recovered by `stateOf`; a slot function is a camelCase
  verb named after its slot, never `impl`; a slot refuses a null first argument; a factory is `export`
  without `pub` and on failure frees what it took and returns a zeroed handle; shared Zig source comes from
  a package named after its concept; tests are named by a sentence and the last one checks for leaks.
- A managed module is PascalCase with no dot. A command line tool exits 0, 1 on failure, 2 when it could
  not run.

### C#

- `///` docs on every `public` and `protected` member, contract only.
- `InternalsVisibleTo` is banned: a native handle crosses assemblies through the `Native` pointer of a
  generated `INative<Domain>` interface, implemented explicitly.

### Git

- Conventional Commits 1.0.0 (`feat`, `fix`, `refactor`, `docs`, `test`, `chore`); a breaking change carries
  `!` and a `BREAKING CHANGE:` footer. No `Co-Authored-By` footer.
- One commit per logical task, staged file by file, never `git add .`. Every commit builds on its own.
- `main` takes commits after `scripts/ci_local.cs` passes on it; work of several commits goes through a
  branch and a `--no-ff` merge. See [`docs/conventions/git.md`](docs/conventions/git.md).

## Rules

Rules a machine can check are checked by `scripts/check_engine_rules.cs`; where one is already broken it
holds a ceiling that only goes down.

**Dissatisfaction is a requirement not yet named.** A design its owner is unsatisfied with is not finished:
name what it fails to honour and design again from that.

1. **A plugin exposes vtables behind one factory per header.** Only the shared kernel library exports plain
   functions.
2. **No `InternalsVisibleTo`.**
3. **Search precedents before inventing, and judge the precedent first.** Find the closest existing case and
   match it. Frequency is not endorsement: much of the code predates the convention that now governs it,
   and old code is refactored, not copied. A workaround, a shortcut, coupling, or anything a rule here
   forbids is debt, never a precedent. The test is "was this chosen, and is it still what we'd choose?";
   when unsure, ask.
4. **Consult legacy before rewriting.** Read what was there, then design the replacement consciously.
5. **No mutex, condition variable or raw thread in a plugin.** Only the job system, the async system and an
   I/O implementation start threads. Producers and consumers are ordered through `ke_completion`,
   dependencies and component access.
6. **A caller's failure is a `ke_result`; an internal invariant is a debug assert.** `abort` and `@panic`
   never appear.
7. **The framework is a plugin like any other**, at `src/zig/framework/`, reached through its contracts.
8. **No magic numbers.** A bare constant only when the algorithm implies it; any other is a setting or a
   factory argument, with the current value as default.
9. **The correct shape beats the easy one.** A design is judged by its shape, never by how much code would
   change. A local workaround for a narrow problem is allowed and named as one.
10. **Code first, files on top.** Everything a file describes is first an API a program calls; the file is
    a loader over that API and reaches nothing the code cannot.
11. **The contract is the product.** A contract serves every way of implementing it, promises only what all
    of them keep, and names another contract's type only where the concept is inherent. An implementation
    starts as the simplest one that keeps the contract, on a third-party library where one exists.
