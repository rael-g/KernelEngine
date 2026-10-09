# How does the build turn the tree into libraries, and where does everything land?

`zig build`, run at the repository root (`build.zig:12` refuses any other directory), is the only
native entry point. The root `build.zig` fetches toolchains, runs vcpkg, and takes every plugin and
every C example into its own build graph as a path dependency (`build.zig.zon`; `Ctx.member` and
`Ctx.example`, `build.zig:1206-1244`). One `zig build` process compiles all of them, with one cache.

## What the build needs from the machine

The project resolves its own dependencies. The machine provides Zig and the .NET SDK, and on Linux the
system's windowing development headers that glfw is built against (`docs/conventions/ci.md`). Everything
else comes through a package manager and is kept under `build/`: the native libraries are vcpkg ports
built from source (`vcpkg.json`), the .NET packages come from NuGet (`nuget.config`), among them the
`libclang` the binding generator loads, and the Zig packages are declared in a `build.zig.zon`. The four
tools no package manager carries, vcpkg itself, `slangc`, `wgpu-native` and RenderDoc, are fetched by
`build.zig` at a pinned version, through `sh`.

So the first build on a machine, or after `build/` is deleted, downloads those packages and tools and
compiles every port, and takes far longer than any later one, which reuses `build/` and rebuilds only what
changed. A slow first build is the project resolving its own dependencies, not a fault.

## Where a dependency comes from

Dependency management is the way a dependency enters the project. It is declared to the package manager
of its language or of the project, which resolves it:

- **vcpkg** for native libraries (`vcpkg.json`).
- **NuGet** for .NET packages (`nuget.config`).
- **`build.zig.zon`** for Zig packages, and for C sources that a `build.zig` compiles. A package there is
  source, built by the build graph for whatever the target is, never a binary chosen per operating
  system.

Two fallbacks exist, in this order, and each is an exception that has to be justified by the package
managers not carrying the thing:

1. **A fetch step in the root `build.zig`**, pinned to a version, into `build/tools/`. It exists so that
   third-party code does not have to be copied into the repository. The tools taken this way are the
   ones in the table under [Fetched tools](#fetched-tools), and the root `build.zig` is the only place
   that fetches: a dependency does not download tools on behalf of the build that uses it.
2. **A vendored copy**, under the rule for vendoring in `CLAUDE.md`.

The machine is never a source. Beyond the prerequisites named above, nothing is looked for in the
environment or installed through the operating system's package manager.

When a tool is wanted and no package manager carries it, the first question is whether a library that
one of them does carry solves the same problem. A fetch step is what is left when the answer is no.

## Where output goes

Everything a build fetches or produces is under `build/`, apart from the `zig-pkg/` described below and two exceptions: the small markers `dotnet run` keeps for each script under `~/.local/share/dotnet/runfile`, which the tool does not let a repository relocate, and NuGet's HTTP cache, which only a command run through `scripts/verify.cs` keeps under `build/nuget/http-cache` (`NUGET_HTTP_CACHE_PATH`, set for every child process there; a `dotnet build` typed by hand writes to `~/.local/share/NuGet`):

| directory | holds |
|---|---|
| `build/tools/` | fetched toolchains: vcpkg, `slangc`, wgpu-native, RenderDoc |
| `build/vcpkg-installed/<triplet>/` | the ports vcpkg installed |
| `build/vcpkg-archives/`, `build/vcpkg-registries/` | vcpkg's binary archives of compiled ports and its registry checkouts; the root build gives `vcpkg install` these paths through `VCPKG_DEFAULT_BINARY_CACHE` and `X_VCPKG_REGISTRIES_CACHE` |
| `build/zig-global/` | Zig's global cache, when the root build is given `--global-cache-dir build/zig-global`, as `scripts/verify.cs` gives it; the vcpkg ports' `zig cc` is always given it |
| `build/nuget/packages/` | NuGet's global packages folder, set by `nuget.config` at the repository root |
| `build/nuget/http-cache/` | NuGet's HTTP cache, set by `scripts/verify.cs` for the commands it runs |
| `build/zig-cache/` | the Zig cache of the one build process, when the root build is given `--cache-dir build/zig-cache`; the vcpkg ports' `zig cc` is always given it |
| `<--prefix>/lib`, `/bin`, `/gen` | plugin libraries, executables, generated shader output |

`--prefix` is the install root the caller picks. The root installs every plugin's library under
`lib` (`build.zig:1212`) and every example's executable under `bin`, named after the example
(`build.zig:1239-1242`), so all of them converge in one tree.

A Zig package is declared by URL and hash in a `build.zig.zon`: `docir` in the root's, `zmath` in
that of each plugin that imports it. Zig 0.16 unpacks every package of a build into `zig-pkg/` beside
the `build.zig` that was invoked and offers no option to move it, so the root build keeps one
`zig-pkg/` at the repository root, ignored by git. It is the one thing a build writes outside
`build/` and outside the user's home.

## Which headers the libraries were built from

After every plugin is built, the root build writes `<--prefix>/abi.stamp`: one line per contract header
(`src/c/**/*.h`) and factory header (`src/zig/**/include/**/*.h`), each a SHA-256 of the file with its
carriage returns removed (`scripts/abi_stamp.zig`). `tests/csharp/KernelEngine.Kernel.Tests/NativeFreshnessTests.cs`
re-hashes those headers under `build/native` and fails, naming the files, when one has changed since
the libraries were built, or when there is no stamp. A library built from an older header still loads,
and nothing else tells it apart from a current one.

## What a plugin receives

A plugin's `build.zig` takes its dependencies as options, never by reading its neighbours: one
include directory per domain it consumes, plus library and source paths
(`src/zig/window/glfw/build.zig:7-14`). Each option is required: the plugin's build panics without
it, and its include paths are exactly the ones it was handed (`glfw/build.zig:23-25`). The root
passes them as the arguments of `b.dependency`, together with its own `target` and `optimize`
(`build.zig:1208`, and any `ctx.member` call). The same `build.zig` still runs alone from its
directory, given the same options as `-D` flags.

A plugin that links another plugin's library takes it from `<--prefix>/lib`, so the root makes its
compile step wait for the steps listed in the `deps` argument of `Ctx.member` (`build.zig:1211`):
the install steps of the plugins it links, and the fetch or shader steps it reads the output of.

## Tests

`Ctx.member` takes a required `Tests` argument, `.has_tests` or `.no_tests` (`build.zig:1078`), so a
plugin cannot be declared without answering the question. For a `.has_tests` plugin the root hangs
the plugin's own `test` step off its `test` step, and makes every test run wait for the installed
libraries, since a test may load one (`build.zig:1217-1221`). The plugin's test module is built
with the options its library was given, because both come from the one `b.dependency` call.

## Fetched tools

| tool | pinned at | fetched by |
|---|---|---|
| vcpkg | `2026-07-13` (`build.zig:18`) | `sh -c 'curl … && tar …'` (`build.zig:28-35`) |
| slangc | `2025.17.2` (`build.zig:65`) | `sh -c 'curl … && unzip …'` (`build.zig:74-79`) |
| wgpu-native | `v24.0.3.1` (`build.zig:324`) | `sh -c …` |
| RenderDoc | `1.46` (`build.zig:402`), with a SHA-256 | `sh -c …` |

vcpkg runs in manifest mode against `vcpkg.json` with the overlay triplets in `vcpkg-triplets/`,
installing into `build/vcpkg-installed`. The triplet is chosen by the target OS: `x64-windows-zig` or
`x64-linux-zig`.

The install step is skipped when the installed tree is current. The root build hashes `vcpkg.json`,
`vcpkg-configuration.json`, every file in `vcpkg-triplets/`, the vcpkg version and the Zig version
building it, and compares the digest with `build/vcpkg-installed/ke-ports.stamp`. A match with the
triplet's `lib/` present leaves vcpkg out of the build graph; any difference, or a missing stamp, runs
vcpkg and writes the stamp afterwards. vcpkg re-evaluates every port on each run otherwise, which on
a Windows runner costs minutes even when nothing was rebuilt.

## Documentation

`zig build docs` writes `<--prefix>/docs/<plugin>.json` and `<plugin>.md` for every plugin, from its
module in the build graph: the plugin's sources, the contract directory named in its `ctx.member`
call and the headers both include. The step comes from `docir`, a dependency of the root
`build.zig.zon` whose `build.zig` the root imports (`build.zig:3`).

## Shaders

Each shader is compiled to WGSL by running `dotnet run scripts/compile_slang.cs` with the fetched
`slangc` (`build.zig:829-849`). An authored material is compiled once per pass: a wrapper that
binds the material into the pass's entry points is generated by
`dotnet run scripts/generate_material_wrapper.cs`, then compiled like any other shader
(`build.zig:889`). **The native build therefore needs the .NET SDK on the path**, not only Zig.

## Windows

The root `build.zig` separates what runs on the machine doing the build (the **host**) from what is built for (the **target**). The target decides the vcpkg triplet and the wgpu-native library; the host decides which `vcpkg` and `slangc` binaries are fetched and run, and the `--host-triplet`.

| what | decided by | Windows | elsewhere |
|---|---|---|---|
| vcpkg triplet | target | `x64-windows-zig` | `x64-linux-zig` |
| wgpu-native | target | `wgpu-windows-x86_64-msvc-release`, `wgpu_native.dll` | `wgpu-linux-x86_64-release`, `libwgpu_native.so` |
| vcpkg binary | host | `vcpkg.exe` | `vcpkg` (the `glibc` asset) |
| `slangc` | host | `slang-<ver>-windows-x86_64`, `slangc.exe` | `slang-<ver>-linux-x86_64` |

That split is what lets a Linux host build the Windows target: `dotnet run scripts/verify.cs -- cross-windows` runs `zig build -Dtarget=x86_64-windows-gnu` into `build/cross-windows`, with the ports installed under their own root, `build/vcpkg-installed-x64-windows-zig`, because a vcpkg manifest root keeps one triplet's packages and installing another would remove the first. It compiles and links every plugin, example and DLL; it does not run any of them, and it cannot reproduce what the Windows runner image brings (its `tar`, its `ccache`).

Every plugin is given the root's target, and the Windows triplet builds vcpkg ports with
`zig cc` through a mingw-style toolchain file, so no Visual Studio or Windows SDK is involved. Both
toolchain files include `vcpkg-triplets/zig-common.cmake`, which names `zig` as the C and C++ compiler
with `cc` and `c++` as its leading argument and archives with `zig ar`, so there is no wrapper script
per command and none per shell; they add only the target system and, for Windows, `-target
x86_64-windows-gnu`. Static archives keep the GNU `lib*.a` naming; assimp's `zlib` and
`minizip` archives are named `libzs.a` and `libminizips[d].a` there (`build.zig:219-230`).

A plugin library is installed under Zig's own per-target name: `<name>.dll` on Windows, with no `lib`
prefix, and `lib<name>.so` elsewhere (`build.zig:977-981`). After every plugin and the wgpu-native
copy are built, the root copies every `*.dll` from `lib/` into `bin/` as well, so that an executable
in `bin/` finds its libraries beside it (`build.zig:546-554`). On other targets nothing is copied to
`bin/`.

## Where the managed build takes the libraries from

The C# projects do not run any of this. Each one that calls a native library copies it from
`<repo>/build/native/lib` into its own output directory, using the platform's prefix and extension
(`src/csharp/NativeDependencies.targets:35-57`); on Windows that is `<name>.dll` from `lib/`, not
from `bin/`. How a project names what it needs, and what happens when the copy is stale, is in
`docs/conventions/managed-build.md`.
