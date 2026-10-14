# How do I load a model into the scene?

This guide adds one thing to the host of [the previous guide](scene-on-screen.md): a model read
from a file. Every passage is quoted from `examples/csharp/12_asset_loading/Program.cs`.

## Register a loader

Reading a file format is the job of a plugin. The host registers the loader it wants, and the
rest of the program asks for `IAssetLoader` without naming it.

[!code-csharp[](../../examples/csharp/12_asset_loading/Program.cs#loader)]

## Load the file and add it to the tree

`LoadModel` returns the data of the file: its meshes, materials and textures. `AddModel` uploads
them through `IRenderResources` and adds one node per mesh, each named after the given root
name and its mesh. The loaded data is disposed once the nodes exist.

[!code-csharp[](../../examples/csharp/12_asset_loading/Program.cs#load)]

## Run it

```bash
zig build --prefix build/native --global-cache-dir build/zig-global
LD_LIBRARY_PATH=build/native/lib dotnet run --project examples/csharp/12_asset_loading
```
