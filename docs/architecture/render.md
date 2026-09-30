# How does a frame get from the ECS to the GPU?

A frame is produced by ordinary runtime systems in `KE_PHASE_RENDER`. There is no render graph
object: ordering comes from the runtime's waves ([runtime.md](runtime.md#waves--what-may-run-concurrently)),
and a render resource is a component id.

## The parts

| part | what it is | where |
|---|---|---|
| GPU device | the device, resource and command contract; one implementation, WebGPU | `src/c/render/kernel_engine/render/gpu/gpu_device.h`; plugin `ke_gpu_device_webgpu` (`build.zig:266`) |
| render service | resources by name, pass recording contexts, meshes, textures, materials, pipeline cache, frame lifecycle | `.../render/service/render_service.h:65`; `src/zig/render/service/` |
| pass plugins | one plugin per pass: shadow, cluster, gbuffer, deferred lighting, skybox, forward, tonemap, UI | `src/zig/render/<pass>/` |
| render module | composes the passes and registers the frame-edge systems | `src/zig/render/module/src/render_module.zig` |

## A resource is a component id

`declare` allocates a transient GPU resource under a name and returns **the tag-component id to put
in a pass's access list** (`render_service.h:69-72`). `import_texture`, `import_buffer`,
`import_bind_group` and `import_tag` do the same for something owned elsewhere or for an ordering
dependency that carries no data (`render_service.h:73-90`). `cid(name)` looks one up (`:91-92`).

So "pass B reads what pass A writes" is written as the runtime already understands access: A lists
the resource's cid with `KE_ACCESS_WRITE`, B with `KE_ACCESS_READ`.

## A pass is a runtime system

A pass plugin's factory takes the runtime, the render service, the device and a logger, sets up its
pipelines, and registers **one system** in `KE_PHASE_RENDER` whose access list names the resources it
reads and writes. The tonemap pass is the smallest example: it reads `hdr`, writes `backbuffer`
(`src/zig/render/tonemap/src/tonemap_module.zig:126-129`) and registers as `render.tonemap` in the
render phase (`tonemap_module.zig:147-170`).

Inside its body a pass opens a recording context with `begin_pass(sys, io)` and closes it with
`end_pass` (`render_service.h:94-100`). `ke_render_pass_io` names the pass's reads and writes and the
command slot it records into (`render_service.h:51-63`). The context resolves those names to views,
and offers a render pass, a compute pass and the raw encoder
(`src/c/render/kernel_engine/render/service/pass_context.h:15-28`).

## The frame has two edges, and they are also systems

`render.begin_frame`, `render.clear` and `render.end_frame` are registered by the render module
(`render_module.zig:305-306`, `379`), each with an access list over the `backbuffer` resource and a
`render.frame` tag (`render_module.zig:231-245`):

| system | backbuffer | `render.frame` |
|---|---|---|
| `render.begin_frame` | write | write |
| `render.clear` | write | read |
| `render.end_frame` | read | write |

`begin_frame` acquires the backbuffer and clears the per-pass command slots
(`render_service.h:102-104`; `src/zig/render/service/src/frame_lifecycle.zig:4-14`). `end_frame`
flushes the queued buffer uploads, finishes every recorded slot, submits them in one call and
presents (`render_service.h:105-106`; `frame_lifecycle.zig:29-75`).

## Two orders, which are not the same order

**Execution order** is the runtime's: systems are placed into waves greedily **in registration
order**, and a conflict only pushes a system into a later wave — it never moves a system ahead of
one registered before it. The access lists therefore keep a reader and a writer of one resource
apart; they do not put the writer first.

**Submission order** is the command slot's. `end_frame` walks slots `0` to `MAX_CMD_BUFFERS - 1`
and submits each one that was recorded (`frame_lifecycle.zig:44-50`, `src/zig/render/service/src/render_service.zig:26`).
Each pass chooses its own slot, as a literal in its own plugin:

| slot | pass | source |
|---|---|---|
| 0 | clear | `render_module.zig:227` |
| 1 | shadow | `shadow_module.zig:234` |
| 2 | cluster cull | `cluster_module.zig:365` |
| 3 | gbuffer | `gbuffer_module.zig:307` |
| 4 | deferred lighting | `deferred_lighting_module.zig:324` |
| 5 | skybox | `skybox_module.zig:188` |
| 6 | forward | `forward_module.zig:437` |
| 7 | tonemap | `tonemap_module.zig:124` |
| caller's | UI | `ui_module.zig:430`, a parameter of its setup |

What reaches the GPU is ordered by slot whatever order the bodies ran in.

## What the render phase reads

Render systems do not read live component storage. Their queries resolve to copies the runtime
extracted after the sim phases ([runtime.md](runtime.md#sim-and-render--how-they-are-decoupled)), and
their structural operations are refused ([runtime.md](runtime.md#structural-change--the-defer-queue)).
