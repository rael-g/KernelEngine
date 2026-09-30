# Documentation

Each entry is the question that document answers. If your question is not one of these, the answer
is in the code, and `CLAUDE.md`'s closing table says where to start looking.

## Architecture

- [How is the engine divided into layers, and where does each kind of file live?](architecture/layers.md)
- [How does a call cross the C ABI, and how does a failure come back?](architecture/abi.md)
- [How does one runtime tick run, and what may run at the same time?](architecture/runtime.md)
- [Which threads exist, what runs on them, and how does work reach them?](architecture/threading.md)
- [What does the ECS contract promise about threads and structural change, and how does the flecs plugin keep it?](architecture/ecs.md)
- [What is the framework made of, and what does each piece depend on?](architecture/framework.md)
- [How does a frame get from the ECS to the GPU?](architecture/render.md)

## Formats

- [What does a scene file say, and what does the loader do with it?](formats/scene-file.md)

## Conventions

- [How does the build turn the tree into libraries, and where does everything land?](conventions/build.md)
- [How is this project's documentation written?](conventions/docs.md)
