# Managed build

A C# project never builds native code. The native build puts every plugin library in
`<--prefix>/lib` (`docs/conventions/build.md`), and each managed project that P/Invokes a library
names it and has MSBuild copy it next to its own assembly. The shared definition is
`src/csharp/NativeDependencies.targets`.

## Where managed output goes

`src/csharp/Directory.Build.props` turns on `UseArtifactsOutput` and sets `ArtifactsPath` to
`<repo>/build/artifacts`; `tests/csharp/Directory.Build.props` does the same. A project's build output is therefore `build/artifacts/bin/<ProjectName>/<config>/`,
for example `build/artifacts/bin/pong/debug/`.

## How a project names its libraries

A project declares the native libraries its P/Invokes load, by file stem without prefix or extension,
and imports the targets file:

```xml
<ItemGroup>
  <NativeDep Include="ke_resource_cache_default" />
</ItemGroup>
<Import Project="../../NativeDependencies.targets" />
```

(`src/csharp/audio/KernelEngine.Audio.MiniAudio/KernelEngine.Audio.MiniAudio.csproj`). A project with a
single library may set the property `<NativeTarget>` instead, which the targets file turns into one
`NativeDep` (`KernelEngine.Window.Glfw.csproj`). The declaration comes before the `Import`, because
the copy item is built from `@(NativeDep)` at the point the file is evaluated.

## What the targets file computes

| value | rule |
|---|---|
| `NativeOS` | `linux`, `osx` or `win` from the host OS |
| extension and prefix | `so` / `lib` on Linux, `dylib` / `lib` on macOS, `dll` / none on Windows |
| `NativeArch` | `x64`, or `arm64` when `Platform` is `arm64` |
| `NativeRID` | `$(NativeOS)-$(NativeArch)` |
| `NativeFinalDir` | `$(NativePrefix)/lib`, where `NativePrefix` is `<repo>/build/native` unless the build sets it |

Each `NativeDep` becomes a `None` item pointing at
`$(NativeFinalDir)/$(NativePre)<name>.$(NativeExt)`, linked by file name alone, with
`CopyToOutputDirectory` set to `PreserveNewest` and `Pack` set to `true` with package path
`runtimes/$(NativeRID)/native`.

The managed side reads `build/native/lib` unless `NativePrefix` is given to the build, so the two agree
when the native build ran with `--prefix build/native` or `NativePrefix` names the prefix it ran with.

## What reaches an executable

The copy is an item of the library project, and an executable that references that project through
`ProjectReference` receives it in its own output directory: the example `pong` imports
no targets file, and its output directory holds `libke_async_enki.so`,
`libke_audio_miniaudio.so` and the other libraries of the projects it references
(`ls build/artifacts/bin/pong/debug`). A library a project does not declare is not
copied.

A plugin that links another library carries an `$ORIGIN` `RUNPATH` (`readelf -d
build/native/lib/libke_audio_miniaudio.so`), so the library it links resolves from the directory the
plugin is in, the native prefix or the assembly's output directory.

## The stale-library trap

The copy is part of an MSBuild build: the `None` item with `CopyToOutputDirectory`
(`NativeDependencies.targets`) is processed when the project builds, and at no other time.
`dotnet run --no-build` and `dotnet test --no-build` run no build target, so they run whatever native
library is already in the output directory, even after `zig build` has replaced the one in
`build/native/lib`. A plain `dotnet run` or `dotnet build` runs the copy and refreshes it.

A library that no project in the reference graph declares as `NativeDep` is never copied.
