# Documentation

Each entry is the question that document answers. If your question is not one of these, the answer
is in the code, and `CLAUDE.md`'s closing table says where to start looking.

## Architecture

- [How does a call cross the C ABI, and how does a failure come back?](architecture/abi.md)
- [How does an asset path become a GPU resource, and what is shared between requests?](architecture/assets.md)
- [How does a Project file reach the value a plugin reads, and how does a change reach it?](architecture/configuration.md)
- [What does the ECS contract promise about threads and structural change, and how does the flecs plugin keep it?](architecture/ecs.md)
- [What is the framework made of, and what does each piece depend on?](architecture/framework.md)
- [What does the GPU device contract promise, and what does the WebGPU backend do with it?](architecture/gpu-device.md)
- [How does a key press reach a system body, and when is its edge visible?](architecture/input.md)
- [How does kabic turn a C header into C#, Zig and C, and what stops it going wrong?](architecture/kabic.md)
- [How is the engine divided into layers, and where does each kind of file live?](architecture/layers.md)
- [How do lights, shadows and image-based light reach a shading pass?](architecture/lighting.md)
- [How does a log event reach a sink?](architecture/logging.md)
- [How does the managed layer meet the native one?](architecture/managed-layer.md)
- [How does an authored material become something a pass can draw?](architecture/materials.md)
- [What does the engine derive from a node type's declaration?](architecture/node-types.md)
- [How do Body2D and Collider2D become a simulation, and what does each tick copy between them?](architecture/physics.md)
- [What happens when a pass asks for a pipeline that has not been compiled yet?](architecture/pipeline-cache.md)
- [How does a frame get from the ECS to the GPU?](architecture/render.md)
- [How does one runtime tick run, and what may run at the same time?](architecture/runtime.md)
- [Which threads exist, what runs on them, and how does work reach them?](architecture/threading.md)
- [How does the engine build view and projection matrices for the device's clip space?](architecture/view-space.md)

## Formats

- [What does an input file say, and what does the loader do with it?](formats/input-file.md)
- [Which keys does a Project file have, and who reads each?](formats/project-file.md)
- [What does a scene file say, and what does the loader do with it?](formats/scene-file.md)

## Conventions

- [How does the build turn the tree into libraries, and where does everything land?](conventions/build.md)
- [What does CI run on a push, and what does it leave out?](conventions/ci.md)
- [How is this project's documentation written?](conventions/docs.md)
- [How does a managed project get the native libraries it calls?](conventions/managed-build.md)
