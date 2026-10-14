# Documentation

Each entry is the question that document answers. If your question is not one of these, the answer
is in the code, and `CLAUDE.md`'s closing table says where to start looking.

## Guides

- [How do I start the engine from my own program?](guides/minimal-host.md)
- [How do I put something on screen?](guides/scene-on-screen.md)
- [How do I load a model into the scene?](guides/load-a-model.md)

## Architecture

- [How does a call cross the C ABI, and how does a failure come back?](architecture/abi.md)
- [How does an asset path become a GPU resource, and what is shared between requests?](architecture/assets.md)
- [How does a Project file reach the value a plugin reads, and how does a change reach it?](architecture/configuration.md)
- [What does the ECS contract promise about threads and structural change, and how does the flecs plugin keep it?](architecture/ecs.md)
- [What is the framework made of, and what does each piece depend on?](architecture/framework.md)
- [What does the GPU device contract promise, and what does the WebGPU backend do with it?](architecture/gpu-device.md)
- [How does a key press reach a system body, and when is its edge visible?](architecture/input.md)
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

## Decisions

- [0001. Each kind of documentation lives where something keeps it true](decisions/0001-each-kind-of-documentation-lives-where-something-keeps-it-true.md)
- [0002. An error record lives in per-thread storage and its message is copied, never allocated](decisions/0002-error-records-are-per-thread-and-never-allocate.md)
- [0003. A plugin sees only the domains it asked for](decisions/0003-one-include-path-per-domain.md)
- [0004. Behavior two plugins share is Zig source passed by the build, not a contract header](decisions/0004-shared-behavior-is-source-not-header.md)
- [0005. A system body records structural changes and the runtime applies them after the wave](decisions/0005-structural-change-recorded-then-applied.md)
- [0006. A failure crosses threads as an error type, and the waiter raises a fresh error](decisions/0006-failure-crosses-threads-as-a-type.md)
- [0007. Reserved entity ids come from a band the world never issues from](decisions/0007-entity-ids-reserved-from-a-band.md)
- [0008. The runtime orders render passes; there is no render graph object](decisions/0008-runtime-is-the-render-graph.md)
- [0009. Commands reach the GPU in command-slot order, chosen by each pass](decisions/0009-submission-order-by-command-slot.md)
- [0010. A pass is never made to wait for a pipeline compile](decisions/0010-pipeline-requests-never-wait.md)
- [0011. A lighting feature that is off binds a neutral resource instead of compiling another shader](decisions/0011-neutral-resources-not-shader-variants.md)
- [0012. Refraction is a term only the forward pass has](decisions/0012-refraction-is-forward-only.md)
- [0013. An authored material names no pass; the build binds it to each consuming pass](decisions/0013-material-bound-to-pass-by-the-build.md)
- [0014. View space and the device clip convention are two contracts](decisions/0014-view-space-independent-of-clip-convention.md)
- [0015. A native handle crosses assemblies through an explicitly implemented INative interface](decisions/0015-native-pointer-through-interface.md)
- [0016. A managed handler's exception is caught at the trampoline and rethrown by the next managed call](decisions/0016-handler-exceptions-do-not-cross-native-frames.md)
- [0017. A configuration read returns the caller's fallback and never fails](decisions/0017-configuration-read-never-fails.md)
- [0018. A cached asset is identified by the key alone, and the key is the path as authored](decisions/0018-asset-key-is-the-authored-path.md)
- [0019. A plugin exposes vtables behind one factory per header](decisions/0019-a-plugin-is-vtables-behind-one-factory.md)
- [0020. A plugin takes no mutex, condition variable or thread of its own](decisions/0020-the-scheduler-is-the-only-synchronisation.md)
- [0021. A failure is a ke_error, never an assert or an abort](decisions/0021-a-failure-is-a-ke-error-never-an-abort.md)
- [0022. The framework is a plugin reached through contracts](decisions/0022-the-framework-is-a-plugin-like-any-other.md)
- [0023. A tuning value is a parameter with a default, not a constant](decisions/0023-a-tuning-value-is-a-parameter.md)
- [0024. The correct shape is chosen over the one that is easy today](decisions/0024-the-narrow-path-is-chosen-over-the-easy-one.md)
- [0025. Each language is written to its own convention](decisions/0025-each-language-follows-its-own-convention.md)
- [0026. A native owner is a pointer with Dispose, not a SafeHandle](decisions/0026-no-safehandle-around-a-native-owner.md)
- [0027. A boolean crosses the ABI as bool](decisions/0027-a-boolean-crosses-the-abi-as-bool.md)
- [0028. The Zig cache and package directories stay at the repository root](decisions/0028-zig-cache-and-zig-pkg-stay-at-the-root.md)
- [0029. The render phase reads copies of query results, not live storage](decisions/0029-render-phase-reads-extracted-copies.md)
- [0030. The shape of a plugin where no language convention applies](decisions/0030-plugin-shape-where-no-language-convention-applies.md)

## Formats

- [What does an input file say, and what does the loader do with it?](formats/input-file.md)
- [Which keys does a Project file have, and who reads each?](formats/project-file.md)
- [What does a scene file say, and what does the loader do with it?](formats/scene-file.md)

## Conventions

- [How does the build turn the tree into libraries, and where does everything land?](conventions/build.md)
- [What does CI run on a push, and what does it leave out?](conventions/ci.md)
- [How does work reach main?](conventions/git.md)
- [How is this project's documentation written?](conventions/docs.md)
- [How does a managed project get the native libraries it calls?](conventions/managed-build.md)
