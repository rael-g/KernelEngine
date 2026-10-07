# What does CI run on a push, and what does it leave out?

One workflow, `.github/workflows/ci.yml`, with two jobs: `build-and-test`, which runs on a push to any
branch and on every pull request, and `main-history`, which runs on a push to `main` only. A newer run for the same workflow and ref cancels the older one,
and a job is stopped after 45 minutes.

## Where it runs

A matrix of `ubuntu-latest` and `windows-latest`. Two targets are what keeps "backend-agnostic" and
"no platform favoritism" honest: the build carries a triplet for each, and only running both shows
that both still pass. `fail-fast` is off, so one platform's failure does not stop the other, and
which of them broke is most of the diagnosis. Every step uses `bash` on both, so each command is
written once and a path or binary name never differs by runner. The Windows leg builds the
`x64-windows-zig` triplet and `-Dtarget=x86_64-windows-gnu` sub-builds that
`docs/conventions/build.md` describes.

## What it runs, in order

| step | command | platforms |
|---|---|---|
| checkout | `actions/checkout@v4` with `lfs: true`, so LFS-tracked fixtures are files and not pointers | both |
| windowing headers | `apt-get install xorg-dev libgl1-mesa-dev libglu1-mesa-dev pkg-config`; vcpkg builds glfw3 from source and needs the system's development headers, which Windows takes from the SDK the runner has | Linux |
| Zig | `mlugg/setup-zig@v2`, version `0.16.0` | both |
| .NET | `actions/setup-dotnet@v4`, `10.0.x` | both |
| vcpkg cache | restores `build/tools` and `build/vcpkg-installed`, keyed on `vcpkg.json`, `vcpkg-configuration.json` and `vcpkg-triplets/**` | both |
| clang headers cache | `build/cache`, keyed on `Kabic.ClangSharpBackend/ClangResourceDir.cs` | Linux |
| NuGet cache | `~/.nuget/packages`, keyed on every `.csproj`, with the OS prefix as fallback | both |
| native build | `dotnet run scripts/verify.cs -- build` | both |
| save vcpkg | saves the vcpkg cache after the build, even when the build failed, unless the restore was a hit | both |
| vcpkg build logs | on failure, the tail of every vcpkg build log | both |
| native tests | `dotnet run scripts/verify.cs -- test-native` | both |
| managed tests | `dotnet run scripts/verify.cs -- test-managed` | both |
| gates | `dotnet run scripts/verify.cs -- gates` | Linux only |

All three caches are for speed and never for correctness: a miss costs the vcpkg ports' build time or
the download, and is repopulated by the build itself. The clang headers are fetched by
`kabic check bindings` into `build/cache` on its first run, and that cache is Linux-only because the gates
are. A vcpkg cache that is restored but whose ports are rebuilt anyway means a package's ABI hash
changed; the triplets pass `PATH` through as untracked for that reason, so a runner-specific `PATH`
does not enter the hash.

`scripts/verify.cs` is the one entry point the local run shares with this workflow: `build` is `zig build --prefix build/native --cache-dir build/zig-cache`, `test-native` the same with `test`, `test-managed` is `dotnet test KernelEngine.slnx`, and `gates` runs every `scripts/check_*.cs` it finds. With no stage it runs all four in that order and prints each step's time. `--keep-going` does not stop at the first failing step.

`dotnet test KernelEngine.slnx` builds every project the solution lists, so each C# example is
compiled, and runs the four projects under `tests/csharp/` (`Configuration`, `Kernel`, `Runtime`, and `Kabic`, whose cases pin the shape each backend emits for a synthetic header).
It runs with no `LD_LIBRARY_PATH` set; no step in the workflow sets one.

The nine gates are the `kabic check` commands `drift`, `bindings`, `api-coverage`, `reconstruction` and `out-params`,
and the engine's scripts `check_abi_layout`, `check_component_fields`, `check_generator_contract` and `check_managed_handwritten`. The scripts are found by `verify.cs` rather than
listed in the workflow, so a gate added under `scripts/` runs without the workflow being edited.
What each one fails on is in
`docs/architecture/kabic.md`. They are Linux-only: they compare generated text against headers and
read no compiler or linker output, so the answer cannot differ by runner.

## What `main-history` checks

Every commit on `main` is a one-line Conventional Commit (`docs/conventions/git.md`), so the changelog is
read from the messages. For the commits a push adds to the first-parent line, the job fails when a subject
is not `feat`, `fix`, `refactor`, `docs`, `test` or `chore` followed by a summary, or when a commit has a
body. It runs after the push, so it reports a violation and does not prevent one.

## What it leaves out

- **Running anything.** No step starts a C or C# example: `grep -n 'c_demo\|examples' ci.yml` finds
  nothing. A defect that only shows when a program starts is not caught here.
- **Coverage.** `scripts/coverage.cs` is not called.
- **Artifacts.** The workflow uploads nothing: the libraries it builds are discarded with the runner.
- **Zig generation.** Nothing calls `kabic zig`; the Zig shape tests of `Kabic.Tests` exercise the Zig
  backend on synthetic shapes only.
