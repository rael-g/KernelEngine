# What does CI run on a push, and what does it leave out?

One workflow, `.github/workflows/ci.yml`, with three jobs: `build-and-test` and `visual`, which run on a push to any
branch and on every pull request, and `main-history`, which runs on a push to `main` only. A newer run for the same workflow and ref cancels the older one,
and a job is stopped after 45 minutes.

## Where it runs

A matrix of `ubuntu-latest` and `windows-latest`. Two targets are what keeps "backend-agnostic" and
"no platform favoritism" honest: the build carries a triplet for each, and only running both shows
that both still pass. `fail-fast` is off, so one platform's failure does not stop the other, and
which of them broke is most of the diagnosis. Every step uses `bash` on both, so each command is
written once and a path or binary name never differs by runner. The Windows leg builds the
`x64-windows-zig` triplet for the `x86_64-windows-gnu` target that
`docs/conventions/build.md` describes.

## What it runs, in order

| step | command | platforms |
|---|---|---|
| checkout | `actions/checkout@v4` with `lfs: true`, so LFS-tracked fixtures are files and not pointers | both |
| windowing headers | `apt-get install xorg-dev libgl1-mesa-dev libglu1-mesa-dev pkg-config`; vcpkg builds glfw3 from source and needs the system's development headers, which Windows takes from the SDK the runner has | Linux |
| Zig | `mlugg/setup-zig@v2`, version `0.16.0` | both |
| .NET | `actions/setup-dotnet@v4`, `10.0.x` | both |
| vcpkg cache | restores `build/tools` and `build/vcpkg-installed`, keyed on `vcpkg.json`, `vcpkg-configuration.json` and `vcpkg-triplets/**` | both |
| clang headers cache | `build/cache`, keyed on `Kabic.Bindings/ClangResourceDir.cs` | Linux |
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

`scripts/verify.cs` is the one entry point the local run shares with this workflow: `build` is `zig build --prefix build/native --cache-dir build/zig-cache`, `test-native` the same with `test`, `test-managed` is `dotnet test KernelEngine.slnx`, `gates` runs every `scripts/check_*.cs` it finds, `docs` generates the reference pages and builds the site with DocFX into `build/docs-site`, failing on
a warning such as a link to a section that does not exist, and `visual` is described below. With no stage it runs those six in that order and prints each step's time. `--keep-going` does not stop at the first failing step. Each stage runs alone when it is the only one named.

Three more stages exist for the Windows target and are run only when named: `cross-windows` builds it, `test-windows` runs its Zig tests under Wine, and `test-managed-windows` builds each project under `tests/csharp/` against the Windows libraries and runs its assembly under Wine with the Windows .NET SDK. `scripts/ci_local.cs -- --windows` runs the three inside the image `scripts/ci/Dockerfile.wine` describes, which is where Wine and that SDK come from.

`dotnet test KernelEngine.slnx` builds every project the solution lists, so each C# example is
compiled, and runs the four projects under `tests/csharp/` (`Configuration`, `Kernel`, `Runtime`, and `Kabic`, whose cases pin the shape each backend emits for a synthetic header).
It runs with no `LD_LIBRARY_PATH` set; no step in the workflow sets one.

The eleven gates are the `kabic check` commands `drift`, `bindings`, `api-coverage`, `reconstruction` and `out-params`,
and the engine's scripts `check_abi_layout`, `check_component_fields`, `check_docs`, `check_engine_rules`, `check_generator_contract` and
`check_managed_handwritten`. `check_docs` checks that a map or a guide names only what the sources declare, that no document
cites a line, and that every document is in the index. `check_engine_rules` checks the rules of `CLAUDE.md` that can be read off the tracked files, each
against a ceiling that can only go down. The scripts are found by `verify.cs` rather than
listed in the workflow, so a gate added under `scripts/` runs without the workflow being edited.
What each one fails on is stated by the check itself, in `src/csharp/kabic/Kabic.Cli/` and in the
scripts. They are Linux-only: they compare generated text against headers and
read no compiler or linker output, so the answer cannot differ by runner.

## What `visual` checks

The job builds the image `scripts/ci/Dockerfile` describes, a base pinned by digest with packages from
one apt snapshot, and runs `verify.cs -- build visual` inside it. `scripts/visual.cs` runs each capture
example with the image's lavapipe software Vulkan driver, and compares the PNG it writes, texel by texel
and with no tolerance, against the one of the same name under `golden/linux-lavapipe/`. The pinned driver
is what makes an exact comparison hold: another driver rounds differently, so the script
refuses to run where lavapipe is not installed. A failure uploads `build/visual` as an artifact, with the images that were drawn.
`scripts/ci_local.cs -- --update-golden` records the goldens from the same image.

## What `capture` checks

`capture` is a stage of `verify.cs` that runs only when named, and no job runs it. `scripts/capture.cs`
starts `c_demo_16 --renderdoc` through the `renderdoccmd` the native build fetched into `build/tools/`,
on the same lavapipe driver, with the Vulkan layer manifest the build wrote beside it. The example then
draws into a render target that has RenderDoc capture its last frame. The script converts the capture
to XML with `renderdoccmd convert`, collects the debug labels the frame's passes were recorded under,
sorts them, and compares the list against `golden/linux-lavapipe/c_demo_16.passes`. The list is sorted
because passes record on several workers at once, so their order in the capture file varies between
runs. The capture stays in `build/capture/linux-lavapipe/`, where RenderDoc opens it; `--update` records
the list.

## What `main-history` checks

Every commit on `main` has a Conventional Commit subject (`docs/conventions/git.md`), so the changelog is
read from the subjects. For the commits a push adds to the first-parent line, the job fails when a subject
is not `feat`, `fix`, `refactor`, `docs`, `test` or `chore` followed by a summary. It runs after the push, so it reports a violation
and does not prevent one.

## What it leaves out

- **Running the examples.** The capture examples `visual` draws are the only ones started. No other C or
  C# example runs, so a defect that only shows when one of them starts is not caught here.
- **Coverage.** `scripts/coverage.cs` is not called.
- **Artifacts.** The libraries it builds are discarded with the runner; the only upload is the images of
  a failed `visual`.
- **Zig generation.** Nothing calls `kabic write zig`; the Zig shape tests of `Kabic.Tests` exercise the Zig
  backend on synthetic shapes only.
