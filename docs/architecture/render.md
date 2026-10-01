# How does a frame get from the ECS to the GPU?

A frame is produced by ordinary runtime systems in `KE_PHASE_RENDER`. There is no render graph
object: ordering comes from the runtime's waves ([runtime.md](runtime.md#waves--what-may-run-concurrently)),
and a render resource is a component id.

## The parts

| part | what it is | where |
|---|---|---|
| GPU device | the device, resource and command contract; one implementation, WebGPU | `src/c/render/kernel_engine/render/gpu/gpu_device.h`; plugin `ke_gpu_device_webgpu` (`build.zig:280`) |
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
(`render_module.zig:301-302`, `379`), each with an access list over the `backbuffer` resource and a
`render.frame` tag (`render_module.zig:227-241`):

| system | backbuffer | `render.frame` |
|---|---|---|
| `render.begin_frame` | write | write |
| `render.clear` | write | read |
| `render.end_frame` | read | write |

`begin_frame` acquires the backbuffer and clears the per-pass command slots
(`render_service.h:102-104`; `src/zig/render/service/src/frame_lifecycle.zig:4-26`). `end_frame`
flushes the queued buffer uploads, finishes every recorded slot, submits them in one call and
presents (`render_service.h:105-106`; `frame_lifecycle.zig:29-90`).

## Two orders, which are not the same order

**Execution order** is the runtime's: systems are placed into waves greedily **in registration
order**, and a conflict only pushes a system into a later wave — it never moves a system ahead of
one registered before it. The access lists therefore keep a reader and a writer of one resource
apart; they do not put the writer first.

**Submission order** is the command slot's. `end_frame` walks slots `0` to `MAX_CMD_BUFFERS - 1`
and submits each one that was recorded (`frame_lifecycle.zig:44-71`, `src/zig/render/service/src/render_service.zig:27`).
Each pass chooses its own slot, as a literal in its own plugin:

| slot | pass | source |
|---|---|---|
| 0 | clear | `render_module.zig:223` |
| 1 | shadow | `shadow_module.zig:232` |
| 2 | cluster cull | `cluster_module.zig:365` |
| 3 | gbuffer | `gbuffer_module.zig:305` |
| 4 | deferred lighting | `deferred_lighting_module.zig:324` |
| 5 | skybox | `skybox_module.zig:188` |
| 6 | forward | `forward_module.zig:432` |
| 7 | tonemap | `tonemap_module.zig:124` |
| caller's | UI | `ui_module.zig:430`, a parameter of its setup |

What reaches the GPU is ordered by slot whatever order the bodies ran in.

## Opaque and transparent surfaces take different passes

A mesh's material carries an `alpha_mode` of `OPAQUE`, `MASK` or `BLEND`
(`src/c/render/kernel_engine/render/handles.h:46-51`), and each mesh also has `layers` that a camera's
`cull_mask` must overlap. The two drawing passes split the meshes between them by asking the service
`material_alpha_mode`:

| pass | draws | how |
|---|---|---|
| gbuffer | every mesh whose mode is not `BLEND` | encodes albedo, normal, roughness, emissive into the G-buffer and writes `depth` (`gbuffer_module.zig:26-45`, `:301-307`) |
| deferred lighting | no mesh: a fullscreen triangle | reads the G-buffer and `depth`, shades every texel, writes `hdr` (`deferred_lighting_module.zig:317-324`) |
| skybox | no mesh | loads `hdr`, reads `depth`, fills the texels geometry left empty (`skybox_module.zig:180-188`) |
| forward | every mesh whose mode is `BLEND`, sorted farthest first | blends into `hdr`, depth-testing against `depth` without writing it (`forward_module.zig:34-62`, `:350-366`) |

The order the four run in is fixed by their command slots (3, 4, 5, 6) and by their access lists: all
four write `hdr` or `depth`, so the runtime never puts two of them in one wave.

Before the forward pass opens its render pass it copies `hdr` into a second texture, `hdr_opaque`
(`forward_module.zig:194`). The refraction term of a blended surface samples that copy, since it cannot
sample the target it is writing. The shading both passes share is in [lighting.md](lighting.md); how a
material becomes a pipeline for each of them is in [materials.md](materials.md).

## What a camera component means

Each pass takes the **first** camera in its query, the first row of the first segment
(`gbuffer_module.zig:115`, `forward_module.zig:181`), and builds its own view and projection from
that camera's world transform and component through the view space
([view-space.md](view-space.md#how-a-camera-component-becomes-a-projection)). A camera's `cull_mask` is
compared with each mesh's `layers`; a mesh is drawn only if they share a bit
(`gbuffer_module.zig:40`). With no camera the gbuffer and deferred-lighting passes still open and close
an empty render pass; the forward and cluster passes return without recording.

## How the host composes the passes

`ke_render_module_create` (declared in `src/zig/render/module/include/kernel_engine/render/module/render_module_create.h`, defined at
`render_module.zig:170`) always creates the render service. Whether it builds the rest depends on its
`default_passes` argument.

- **`default_passes` non-zero.** It registers the camera, light, mesh, skybox, sprite and label components with
  their generated field tables, the systems that resolve meshes, sprites and labels in `KE_PHASE_UPDATE`,
  the frame bracket, and then creates the passes in dependency order: shadow, cluster, gbuffer, deferred
  lighting, skybox, forward, tonemap, UI (`render_module.zig:240-353`). If any pass fails to be
  created, the service is destroyed and the call returns an empty handle.
- **`default_passes` zero.** Only the service exists. The host reaches it through
  `ke_render_module_core` (`render_module.zig:103-106`) and composes whichever passes it wants by calling
  their factories itself.

The remaining parameters are all optional: `ke_render_cluster_params` (grid and lights per cluster),
`ke_render_feature_params` (`enable_shadows`, `enable_ibl`; absent means both on,
`render_module.zig:216-217`), `ke_render_shadow_params`, and a `ke_view_space` (absent means the
module creates and owns the right-handed one, `render_module.zig:242-246`). A zero field in a params
struct selects its default.

## What a pass may record, and when it reaches the GPU

A pass records through the context `begin_pass` returned. Three things are worth knowing about that
context.

**Compute is recorded through a proxy.** `begin_compute` does not return the device's compute pass. It
returns a recorder owned by the service, one per command slot, that stores `set_pipeline`,
`set_bind_group`, `dispatch` and `dispatch_indirect` as plain records, at most 32 per slot
(`pass_recording.zig:109-156`, `render_service.zig:78-90`). `end_pass` marks the slot as a compute slot
rather than a finished one (`pass_recording.zig:35-47`). `end_frame` then opens a real compute pass on
that slot's encoder, replays the records in order, ends it and finishes the buffer
(`frame_lifecycle.zig:49-70`). So a dispatch reaches the device at `end_frame`, in slot order, not at the
moment the pass body calls it. The cluster cull is the one user (`cluster_module.zig:204-209`).

**Uploads are staged.** `upload(buffer, offset, data, size)` does not touch the device. It reserves space
in an 8 MiB arena and a record slot with atomic counters, copies the bytes into the arena and appends the
record, so systems running on different workers can call it without a lock
(`frame_lifecycle.zig:93-103`, `render_service.zig:30`, `:32`). `end_frame` writes every record to its
buffer with the device's `write_buffer` before it submits anything (`frame_lifecycle.zig:34-39`);
`begin_frame` resets both counters (`frame_lifecycle.zig:13-14`). An upload past 4096 records or past the
arena is dropped without an error.

**The rest of the device is reachable.** `encoder()` returns the slot's raw command encoder, which the
forward pass uses for its texture copy (`forward_module.zig:194`). `query_ext(name)` forwards to the
device's `query_extension` (`pass_recording.zig:162-165`). Storage buffers, indirect commands and storage
textures are part of the device contract itself, described in [gpu-device.md](gpu-device.md); pipeline
requests go through [pipeline-cache.md](pipeline-cache.md).

## What the render phase reads

Render systems do not read live component storage. Their queries resolve to copies the runtime
extracted after the sim phases ([runtime.md](runtime.md#sim-and-render--how-they-are-decoupled)), and
their structural operations are refused ([runtime.md](runtime.md#structural-change--the-defer-queue)).
