# What does CI run on a push, and what does it leave out?

One workflow, `.github/workflows/ci.yml`, with one job, `build-and-test`. It runs on a push to any
branch and on every pull request (`ci.yml:12-15`). A newer run for the same workflow and ref cancels
the older one (`ci.yml:17-19`).

## Where it runs

A matrix of `ubuntu-latest` and `windows-latest` (`ci.yml:26-34`). `fail-fast` is off, so one
platform's failure does not stop the other. Every step uses `bash` on both (`ci.yml:36-40`), so each command is written once. The Windows leg builds the
`x64-windows-zig` triplet and `-Dtarget=x86_64-windows-gnu` sub-builds that `docs/conventions/build.md`
describes.

## What it runs, in order

| step | command | platforms |
|---|---|---|
| windowing headers | `apt-get install xorg-dev libgl1-mesa-dev libglu1-mesa-dev pkg-config` (`ci.yml:49-53`) | Linux |
| Zig | `mlugg/setup-zig@v2`, version `0.16.0` (`ci.yml:55-57`) | both |
| .NET | `actions/setup-dotnet@v4`, `10.0.x` (`ci.yml:59-61`) | both |
| vcpkg cache | `build/tools` and `build/vcpkg-installed`, keyed on `vcpkg.json`, `vcpkg-configuration.json` and `vcpkg-triplets/**` (`ci.yml:68-73`) | both |
| clang headers cache | `.cache`, keyed on `scripts/generate_bindings.cs` (`ci.yml:80-85`) | Linux |
| NuGet cache | `~/.nuget/packages`, keyed on every `.csproj` and `src/csharp/dotnet-tools.json`, with the OS prefix as fallback (`ci.yml:87-92`) | both |
| native build | `dotnet run scripts/verify.cs -- build` (`ci.yml:95`) | both |
| native tests | `dotnet run scripts/verify.cs -- test-native` (`ci.yml:102`) | both |
| managed tests | `dotnet run scripts/verify.cs -- test-managed` (`ci.yml:105`) | both |
| gates | `dotnet run scripts/verify.cs -- gates` (`ci.yml:116`) | Linux only |

`scripts/verify.cs` is the one entry point the local run shares with this workflow: `build` is `zig build --prefix build/native --cache-dir build/zig-cache`, `test-native` the same with `test`, `test-managed` is `dotnet test KernelEngine.slnx`, and `gates` runs every `scripts/check_*.cs` it finds. With no stage it runs all four in that order and prints each step's time. `--keep-going` does not stop at the first failing step.

The vcpkg cache only speeds the run up: a miss is repopulated by the build itself, because the build
fetches vcpkg into `build/tools` and installs ports into `build/vcpkg-installed` on its own
(`docs/conventions/build.md`).

`dotnet test KernelEngine.slnx` builds every project the solution lists, so each C# example is
compiled, and runs the three projects under `tests/csharp/` (`Configuration`, `Kernel`, `Runtime`).
It runs with no `LD_LIBRARY_PATH` set; no step in the workflow sets one.

The eleven gates are `check_abi_layout`, `check_api_coverage`, `check_api_drift`, `check_bindings_drift`, `check_component_fields`,
`check_generator_contract`, `check_generator_shapes`, `check_managed_handwritten`,
`check_out_params`, `check_reconstruction` and `check_zig_shapes`, found by `verify.cs` rather than
listed in the workflow; `check_generator_shapes` and `check_zig_shapes` are run with `--no-cache`
(`scripts/verify.cs`, `Gates`). What each one fails on is in
`docs/architecture/kabic.md`. They are Linux-only: they compare generated text against headers and
read no compiler or linker output.

## What it leaves out

- **`scripts/generate_rsp.cs --check`.** The check that every `.rsp` equals what the headers imply
  exists (`generate_rsp.cs:254-270`) and `ci.yml` does not call it.
- **Running anything.** No step starts a C or C# example: `grep -n 'c_demo\|examples' ci.yml` finds
  nothing. A defect that only shows when a program starts is not caught here.
- **Coverage.** `scripts/coverage.cs` is not called.
- **Artifacts.** The workflow uploads nothing: the libraries it builds are discarded with the runner.
- **Zig generation.** Nothing calls `scripts/generate_zig.cs`; `check_zig_shapes` exercises the Zig
  backend on synthetic shapes only.
