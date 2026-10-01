# How does a managed project get the native libraries it calls?

A C# project never builds native code. The native build puts every plugin library in
`<--prefix>/lib` (`docs/conventions/build.md`), and each managed project that P/Invokes a library
names it and has MSBuild copy it next to its own assembly. The shared definition is
`src/csharp/NativeDependencies.targets`.

## Where managed output goes

`src/csharp/Directory.Build.props` turns on `UseArtifactsOutput` and sets `ArtifactsPath` to
`<repo>/build/artifacts` (`Directory.Build.props:4-5`); `tests/csharp/Directory.Build.props` does the
same (`:4-5`). A project's build output is therefore `build/artifacts/bin/<ProjectName>/<config>/`,
for example `build/artifacts/bin/00_runtime_minimal/debug/`.

## How a project names its libraries

A project declares the native libraries its P/Invokes load, by file stem without prefix or extension,
and imports the targets file:

```xml
<ItemGroup>
  <NativeDep Include="ke_logger_simple" />
</ItemGroup>
<Import Project="../../NativeDependencies.targets" />
```

(`src/csharp/logger/KernelEngine.Logger/KernelEngine.Logger.csproj:10-14`). A project with a single
library may set the property `<NativeTarget>` instead, which the targets file turns into one
`NativeDep` (`NativeDependencies.targets:59-61`; `KernelEngine.Window.Glfw.csproj:8`). The declaration
comes before the `Import`, because the copy item is built from `@(NativeDep)` at the point the file
is evaluated (`NativeDependencies.targets:63-64`).

## What the targets file computes

| value | rule | lines |
|---|---|---|
| `NativeOS` | `linux`, `osx` or `win` from the host OS | `3-13` |
| extension and prefix | `so` / `lib` on Linux, `dylib` / `lib` on macOS, `dll` / none on Windows | `35-48` |
| `NativeArch` | `x64`, or `arm64` when `Platform` is `arm64` | `23-28` |
| `NativeRID` | `$(NativeOS)-$(NativeArch)` | `30-33` |
| `NativeFinalDir` | `<repo>/build/native/lib` | `50-57` |

Each `NativeDep` becomes a `None` item pointing at
`$(NativeFinalDir)/$(NativePre)<name>.$(NativeExt)`, linked by file name alone, with
`CopyToOutputDirectory` set to `PreserveNewest` and `Pack` set to `true` with package path
`runtimes/$(NativeRID)/native` (`NativeDependencies.targets:63-71`).

`NativeFinalDir` is `build/native/lib` in the file itself. The managed side reads that directory
whatever `--prefix` the native build was given, so the two agree only when the native build ran with
`--prefix build/native`.

## What reaches an executable

The copy is an item of the library project, and an executable that references that project through
`ProjectReference` receives it in its own output directory: the example `00_runtime_minimal` imports
no targets file, and its output directory holds `libke_common.so`, `libke_ecs_flecs.so`,
`libke_input_default.so` and the other libraries of the projects it references
(`ls build/artifacts/bin/00_runtime_minimal/debug`). A library a project does not declare is not
copied.

On a Linux build the plugin libraries carry an absolute `RUNPATH` naming `<prefix>/lib`
(`readelf -d build/native/lib/libke_framework.so`), so a library that one plugin links against
resolves from the native prefix whether or not a copy sits beside the assembly.

## The stale-library trap

The copy is part of an MSBuild build: the `None` item with `CopyToOutputDirectory`
(`NativeDependencies.targets:66`) is processed when the project builds, and at no other time.
`dotnet run --no-build` and `dotnet test --no-build` run no build target, so they run whatever native
library is already in the output directory, even after `zig build` has replaced the one in
`build/native/lib`. A plain `dotnet run` or `dotnet build` runs the copy and refreshes it.

A library that no project in the reference graph declares as `NativeDep` is never copied.
