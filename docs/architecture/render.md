# Render

This is a map: the parts of the render domain, what each receives and what it hands on. How a
part works inside is on the generated page of its file. Contracts are under `src/c/render/`,
plugins under `src/zig/render/`.

## The parts

| part | contract | plugin | receives | hands on |
|---|---|---|---|---|
| device | `ke_gpu_device` | webgpu | optionally a `ke_async` | GPU objects, command encoders, the clip-space convention |
| target | `ke_gpu_render_target` | webgpu, texture_target, renderdoc_target | the device, and a `ke_window` for the window target; the capture target wraps another target | the texture a frame ends in, and its presentation |
| service | `ke_render_service` | service | device, target, `ke_io`, the resource binder | meshes, textures, materials, pipelines, shaders, uploads, the frame globals |
| graph | `ke_render_graph` | render_graph/simple | the device | the order of a frame's passes, their resources and transitions |
| camera | `ke_render_camera` | camera | `ke_view_space`, the clip-space convention | view and projection matrices from a camera component |
| scene | `ke_render_scene_resolve` | scene | the main and the render world, `ke_extraction`, service | the scene's component ids in both worlds, and the meshes, sprites and fonts they name |
| frame | `ke_render_frame` | frame | the render world, graph, service, camera, scene | the frame every pass declares into, and its begin and end |
| pass | `ke_owner` | one plugin per pass | the service, device, frame and scene it uses, and the schedule and set of each hook | the passes it declares into the frame |

No plugin composes the renderer. The host creates the service, the graph, the camera, the scene,
the frame and the passes it wants, giving each pass the schedule and set of each of its hooks.

## What ties the parts together

**Passes read the render world.** `ke_extraction` copies the scene's components from the main
world into the render world when the scheduler runs it, before the render schedule; an entity carrying
a drawable component gets a pair there. The scene's systems run in the main world and resolve
names into handles before the copy.

**A pass registers its systems when it is made.** Its factory takes a schedule and a set per
hook: `render_prepare` for what it makes for others, `render_queue` for its passes; destroying the
pass unregisters them. The frame's systems take `render_begin` and `render_submit`.

**The graph orders the passes.** A pass declares to `ke_render_graph` the resources it uses and a
record callback. The graph orders passes by their uses, then by injection point, which is the
pass's `ke_render_stage`; it drops a pass nothing needs, and records and submits the rest when the
frame ends.

**Resources between passes are published by name.** A pass that makes something for another
publishes it in the frame under a name of `resource_groups.h`; the reader finds it there in the
same frame, or meets the neutral resource when nobody published it.

**The colour and the output are fixed for the frame.** Stages up to `KE_RENDER_STAGE_HDR_POST`
draw into the frame's colour, later ones into its output. The tonemap pass writes the whole output
and claims it; otherwise the frame copies the colour there.

**A pipeline is asked for, never waited for.** A pass asks the service for a pipeline each time
it draws; the first request returns a placeholder and the real one replaces it when compiled.

## The default passes

| pass | stage | uses | publishes |
|---|---|---|---|
| frame clear | prepass | clears the colour and the depth | |
| shadow | prepass | the light buffer | the shadow map and light |
| cluster | prepass | writes the cluster lists | the light lists and the grid |
| gbuffer | prepass | the depth | the albedo, normal and emissive targets |
| deferred lighting | opaque | the gbuffer, the depth, the shadow and clusters | |
| skybox | sky | samples the depth | |
| forward | transparent | a copy of the colour, the depth, the shadow and clusters | |
| tonemap | tonemap | reads the colour, writes the output | |
| ui | overlay | draws over the output | |

Opaque and alpha-masked surfaces go through gbuffer and deferred lighting; blended ones through
forward, which shades them itself.

## What the parts agree on without a contract

- The layout of the per-frame uniform of each shading pass, between the Zig struct of the pass
  and the `frame` block of its shader.
- The name a shader is loaded by: the pass name for a pass, the material name followed by the
  pass name for a material.

## A feature that is off

Shadows, clustered lights and image-based light are never compiled out of a shader. A feature
that is off binds a neutral resource in its place (a white texture for the shadow map, a black
cube for the environment), so the shading passes have one shader each whatever the host
enables.
