# What happens when a pass asks for a pipeline that has not been compiled yet?

This is a map: the parts that take part in a pipeline request and what each hands on. How the
cache works inside is on the generated page of its file.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| pass | a render system | its own `ke_gpu_render_pipeline_params` | the pipeline it was answered with, to `set_pipeline` |
| service | `get_or_create_pipeline` of `ke_render_service` | the params of the pass | the current pipeline of that request |
| cache | `PipelineCache` in `pipeline_cache.zig` of the service plugin | the params, reduced to a `PsoKey` | the fallback, then the real pipeline |
| device | `create_render_pipeline_async` and `flush_pipeline_compiles` of `ke_gpu_device` | the params and a completion callback | the compiled pipeline, to the callback |
| scheduler | `ke_scheduler`, handed to the device at creation | the compile job | the worker the job runs on |

## What ties the parts together

**A request never waits.** The first request for a set of params returns a fallback pipeline
at once; the same request answered later returns the compiled one. A compile that fails leaves
the fallback in place.

**The cache is the policy, the device is the primitive.** The device compiles and reports
through a callback; the cache decides what is returned meanwhile, and shares one entry between
equal requests.

**Requests may come from several workers at once.** The cache is asked without a lock, and
equal requests that race end on one entry.

**Teardown follows the callback.** A completion callback writes into a cache entry, so the
service flushes the device's compiles (`flush_pipeline_compiles`) before it destroys the cache.

**Where the compile runs depends on the device.** The webgpu device compiles on the scheduler
it was created with, and on the calling thread when it has none or has too many compiles
outstanding; the callback has then already run when the request returns.

## What the parts agree on without a contract

- The vertex layout is part of the key by the address of its array, not by what it holds. A
  pass that wants its requests to share an entry keeps its layout in storage that outlives the
  requests.
- The fallback replaces the fragment stage with a generated shader whose entry point is
  "fs_main" and which writes magenta to every colour target of the request.
