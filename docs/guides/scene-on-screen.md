# Put something on screen

This guide starts from the host of [the first guide](minimal-host.md) and adds a renderer, a
scene and a node that moves. Every passage is quoted from
`examples/csharp/01_window_scene/Program.cs`.

## Add the modules

Three more modules join the window: the renderer, which is given the directory of the compiled
shaders, the framework, which brings the scene tree, and the module that fills the scene.

[!code-csharp[](../../examples/csharp/01_window_scene/Program.cs#modules)]

## Fill the scene

`SceneNodesModule` takes a callback that receives the scene tree and the service provider. A
scene is made of nodes added to the tree: here a light, a camera and one mesh. The mesh and its
material are created through `IRenderResources`, which hands back handles the node keeps.

[!code-csharp[](../../examples/csharp/01_window_scene/Program.cs#scene)]

## Give a node behavior

A node type with behavior derives from a node type of the engine, declares `HasBehavior` and
overrides `OnUpdate`. What it reads and writes are its own properties; the time of the frame
arrives in the view it is given.

[!code-csharp[](../../examples/csharp/01_window_scene/Program.cs#behavior)]

## Run it

```bash
zig build --prefix build/native --global-cache-dir build/zig-global
dotnet run --project examples/csharp/01_window_scene
```
