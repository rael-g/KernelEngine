# Documentation

Each entry is a page of the documentation. The site built from these pages is
https://rael-g.github.io/KernelEngine/ ; `CLAUDE.md`'s closing table says where to look when the
answer is in the code.

## Guides

- [Start the engine from your own program](guides/minimal-host.md)
- [Put something on screen](guides/scene-on-screen.md)
- [Load a model into the scene](guides/load-a-model.md)

## Architecture

- [Layers](architecture/layers.md)
- [The C ABI](architecture/abi.md)
- [Managed layer](architecture/managed-layer.md)
- [Runtime](architecture/runtime.md)
- [Threading](architecture/threading.md)
- [ECS](architecture/ecs.md)
- [Framework](architecture/framework.md)
- [Node types](architecture/node-types.md)
- [Render](architecture/render.md)
- [GPU device](architecture/gpu-device.md)
- [Pipeline cache](architecture/pipeline-cache.md)
- [Lighting](architecture/lighting.md)
- [Materials](architecture/materials.md)
- [View space](architecture/view-space.md)
- [Assets](architecture/assets.md)
- [Input](architecture/input.md)
- [Physics](architecture/physics.md)
- [Configuration](architecture/configuration.md)
- [Logging](architecture/logging.md)

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

## Conventions

- [Documentation](conventions/docs.md)
- [Git](conventions/git.md)
- [Build](conventions/build.md)
- [Managed build](conventions/managed-build.md)
- [Continuous integration](conventions/ci.md)

## Formats

- [Project file](formats/project-file.md)
- [Scene file](formats/scene-file.md)
- [Input file](formats/input-file.md)
