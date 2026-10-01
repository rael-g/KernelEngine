# What happens when a pass asks for a pipeline that has not been compiled yet?

It gets a placeholder immediately, and the real pipeline replaces it on a later call. A pass never
waits for a shader compile. The service's `get_or_create_pipeline` (`render_service.h:191-195`) is the
policy layer; the device's `create_render_pipeline_async` is the primitive underneath it
([gpu-device.md](gpu-device.md#pipelines-compile-off-the-callers-thread)).

## What the cache is keyed on

`PsoKey` is built from a `ke_gpu_render_pipeline_params` (`pipeline_cache.zig:8-46`): both shader
modules, both entry-point names (copied into 64-byte arrays), topology, cull mode, front face, the vertex
buffer count, blend state, depth and stencil state, the bind group layouts, alpha-to-coverage and the
colour target formats. Two requests with equal keys share one entry.

The vertex layout contributes the **address** of the `vertex_buffers` array, not what it contains
(`pipeline_cache.zig:16`, `:35`). A pass that wants its requests to hit the same entry keeps its layout
in storage that outlives the request, as the gbuffer and forward passes do by holding it in their module
state (`gbuffer_module.zig:60-61`, `forward_module.zig:83-84`).

## One request, step by step

`getOrCreatePipeline` (`pipeline_cache.zig:244-278`):

1. **Hit.** The key is in the map. If the entry's state is `ready` it returns the real pipeline;
   otherwise it returns the entry's fallback.
2. **Miss.** It allocates an entry in state `pending`, builds a **fallback pipeline** from the same
   parameters with the fragment stage replaced, inserts the entry, asks the device to compile the real
   pipeline asynchronously, and returns the fallback.

The fallback's fragment shader is generated WGSL that writes opaque magenta to every colour target,
sized to the request's `color_target_count` (`pipeline_cache.zig:205-243`). The modules are
cached per target count. A magenta surface on screen therefore means a request that has not yet
resolved.

When the device calls back, `onRealPipelineReady` stores the pipeline in the entry and sets the state to
`ready` with release ordering; a reader's acquire load sees it (`pipeline_cache.zig:69-74`).
A callback carrying the invalid handle leaves the entry `pending`, so a pipeline that fails to compile
keeps returning its fallback on every later call.

Two allocation failures (the entry, the publication of a table that holds it) degrade to a synchronous
`create_render_pipeline` call that leaves no entry behind. The completion context is the entry itself, so
there is no third allocation whose failure could leave an entry `pending` for good.

## Concurrent requests

Passes in one wave ask for pipelines from different threads, and the contract forbids a lock. The table is
a snapshot nobody mutates after publishing it: a lookup loads the current snapshot and probes it; a miss
builds its entry, then publishes a copy of the snapshot that holds it with one compare-and-swap. A
request that loses the swap looks again; if another thread published the same key meanwhile, it destroys
the fallback it had built, never started its compile, and answers with the winner's entry. Replaced
snapshots are kept on a list until the cache is destroyed, because a reader may still be probing one. The
magenta fragment module for each target count is published the same way.

## Where the compile runs

On the WebGPU backend, when the device was created with a scheduler, the compile is dispatched to that
worker pool and the completion callback runs on the worker that did the compile
(`gpu_device_webgpu.zig:989-999`, `:998-1035`). Without a scheduler, or with `MAX_PENDING_COMPILES` = 64
compiles already outstanding, the device compiles synchronously inside the call,
and the callback has already fired when `create_render_pipeline_async` returns
(`:1003-1024`). Even then the first call to the cache returns the fallback, and the real pipeline
appears on the next.

Finished compile tasks are reaped when the device presents (`gpu_device_webgpu.zig:505-523`).

## Shutdown

Destroying the render service first calls the device's `flush_pipeline_compiles`, which waits for every
compile still in flight, and only then destroys the cache's pipelines
(`render_service.zig:189`, `:210`). The order is the contract: a callback writes into a cache entry, so
the cache cannot be destroyed while one may still run (`gpu_device.h:350-355`).

## Who calls it

Every pass that draws asks for its pipeline through this cache rather than the device: the shadow pass
at setup and every frame (`shadow_module.zig:104`, `:215`), the gbuffer and forward passes for each draw
after loading the material's modules ([materials.md](materials.md#how-a-pass-draws-with-it)), and the
deferred-lighting pass (`deferred_lighting_module.zig:196`). The cull pass is a compute pass and uses
`create_compute_pipeline` directly (`cluster_module.zig:352`); the cache holds render pipelines only.
