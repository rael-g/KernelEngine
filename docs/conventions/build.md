# How does the build turn the tree into libraries, and where does everything land?

`zig build`, run at the repository root (`build.zig:8` refuses any other directory), is the only
native entry point. The root `build.zig` builds no plugin itself: it fetches toolchains, runs vcpkg,
and invokes every plugin's own `build.zig` as a separate `zig build` (`Ctx.plugin`, `build.zig:911-939`).

## Where output goes

Everything a build fetches or produces is under `build/`, with two exceptions: the small markers `dotnet run` keeps for each script under `~/.local/share/dotnet/runfile`, which the tool does not let a repository relocate, and NuGet's HTTP cache, which only a command run through `scripts/verify.cs` keeps under `build/nuget/http-cache` (`NUGET_HTTP_CACHE_PATH`, set for every child process there; a `dotnet build` typed by hand writes to `~/.local/share/NuGet`):

| directory | holds |
|---|---|
| `build/tools/` | fetched toolchains: vcpkg, `slangc`, wgpu-native |
| `build/vcpkg-installed/<triplet>/` | the ports vcpkg installed |
| `build/vcpkg-archives/`, `build/vcpkg-registries/` | vcpkg's binary archives of compiled ports and its registry checkouts; the root build gives `vcpkg install` these paths through `VCPKG_DEFAULT_BINARY_CACHE` and `X_VCPKG_REGISTRIES_CACHE` |
| `build/zig-global/` | Zig's global cache; every `zig build` the root build launches, and the vcpkg ports' `zig cc`, are given it, and `scripts/verify.cs` passes it to the root build |
| `build/nuget/packages/` | NuGet's global packages folder, set by `nuget.config` at the repository root |
| `build/nuget/http-cache/` | NuGet's HTTP cache, set by `scripts/verify.cs` for the commands it runs |
| `build/zig-cache/` | the root build's Zig cache; `plugins/<name>/` inside it is one cache per plugin, test and example build |
| `<--prefix>/lib`, `/bin`, `/gen` | plugin libraries, executables, generated shader output |

`--prefix` is the install root the caller picks; every plugin build is invoked with that same prefix
(`build.zig:914`) and installs its library under `lib` (`src/zig/window/glfw/build.zig:54-56`), so all
plugin libraries converge in one `lib/`. `Ctx.cache_dir` is the fixed
`build/zig-cache` path (`build.zig:18`, `91`), whatever `--cache-dir` the caller gave the root; each
sub-build gets `<cache_dir>/plugins/<name>` as its `--cache-dir` (`build.zig:976`, `992`, `1016`).
Sub-builds that shared one cache serialized on its manifest lock, so the caches are separate.

## Which headers the libraries were built from

After every plugin is built, the root build writes `<--prefix>/abi.stamp`: one line per contract header
(`src/c/**/*.h`) and factory header (`src/zig/**/include/**/*.h`), each a SHA-256 of the file with its
carriage returns removed (`scripts/abi_stamp.zig`). `tests/csharp/KernelEngine.Kernel.Tests/NativeFreshnessTests.cs`
re-hashes those headers under `build/native` and fails, naming the files, when one has changed since
the libraries were built, or when there is no stamp. A library built from an older header still loads,
and nothing else tells it apart from a current one.

## What a plugin receives

A plugin's `build.zig` runs standalone and takes its dependencies as `-D` options, never by reading
its neighbours: one include directory per domain it consumes, plus library paths
(`argF(b, "ke-asset-include", …)`, `build.zig:510-523`; `src/zig/window/glfw/build.zig:7-14`). Each
option is required: the plugin's build panics without it (`glfw/build.zig:7-14`), and its include
paths are exactly the ones it was handed (`glfw/build.zig:23-25`).

`Ctx.plugin` also passes `--release=off` or `--release=fast` from the root's optimize mode
(`build.zig:87`) and `-Dtarget=x86_64-windows-gnu` when the root target is Windows
(`build.zig:89`); on every other OS no target is passed and the plugin builds for the host.

## Tests

`Ctx.plugin` takes a required `Tests` argument, `.has_tests` or `.no_tests` (`build.zig:804`), so a
plugin cannot be declared without answering the question. A `.has_tests` plugin gets a second
`zig build test` invocation, given the same `-D` options as its library build, hung off the root's
`test` step (`build.zig:924-936`).

## Fetched tools

| tool | pinned at | fetched by |
|---|---|---|
| vcpkg | `2026-07-13` (`build.zig:18`) | `sh -c 'curl … && tar …'` (`build.zig:28-35`) |
| slangc | `2025.17.2` (`build.zig:65`) | `sh -c 'curl … && unzip …'` (`build.zig:74-79`) |
| wgpu-native | `v24.0.3.1` (`build.zig:258`) | `sh -c …` (`build.zig:271-277`) |

vcpkg runs in manifest mode against `vcpkg.json` with the overlay triplets in `vcpkg-triplets/`,
installing into `build/vcpkg-installed`. The triplet is chosen by the target OS: `x64-windows-zig` or
`x64-linux-zig`.

The install step is skipped when the installed tree is current. The root build hashes `vcpkg.json`,
`vcpkg-configuration.json`, every file in `vcpkg-triplets/`, the vcpkg version and the Zig version
building it, and compares the digest with `build/vcpkg-installed/ke-ports.stamp`. A match with the
triplet's `lib/` present leaves vcpkg out of the build graph; any difference, or a missing stamp, runs
vcpkg and writes the stamp afterwards. vcpkg re-evaluates every port on each run otherwise, which on
a Windows runner costs minutes even when nothing was rebuilt.

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

Every plugin is told `-Dtarget=x86_64-windows-gnu`, and the Windows triplet builds vcpkg ports with
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
