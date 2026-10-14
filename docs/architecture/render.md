# Render

This is a map: the parts of the render domain, what each receives and what it hands on. How a
part works inside is on the generated page of its file. Contracts are under `src/c/render/`,
plugins under `src/zig/render/`.

## The parts

| part | contract | plugin | receives | hands on |
|---|---|---|---|---|
| device | `ke_gpu_device` | webgpu | optionally a `ke_scheduler` and a `ke_logger` | GPU objects, command encoders, the clip-space convention |
| target | `ke_gpu_render_target` | webgpu, texture_target, renderdoc_target | the device, and a `ke_window` for the window target; the capture target wraps another target | the texture a frame ends in, and its presentation |
| service | `ke_render_service` | service | device, target, `ke_ecs` | named resources, passes, uploads, materials, pipelines |
| camera | `ke_render_camera` | camera | `ke_view_space`, the clip-space convention | view and projection matrices from a camera component |
| pass | none; a `ke_runtime_system_params` and a `ke_render_pass_io` | one plugin per pass | `ke_runtime`, service, device, component ids | commands recorded into its slot |
| module | none; `ke_render_module_create` | module | everything above, plus `ke_runtime` | a composed pipeline, and the service to the host |

A host that wants the default pipeline calls `ke_render_module_create` and nothing else of this
table. A host that composes its own creates the service and the passes it wants.

## What ties the parts together

**The runtime is the render graph.** There is no graph object. A render resource is a component
id: a pass declares or imports a resource by name through the service and receives an id, and
puts that id in the access list of its system. The runtime orders and separates the passes from
those access lists, as it does for any other system.

**A pass is a system in `KE_PHASE_RENDER`.** Its `ke_render_pass_io` names what it reads and
writes and the command slot it records into. Between `begin_pass` and `end_pass` it records
through `ke_gpu_render_pass`; nothing reaches the GPU until the frame closes.

**A frame has two edges, which are systems too.** The module registers "render.begin_frame",
which acquires the target, and "render.end_frame", which submits the recorded slots in slot
order and presents. Slot order, not registration order, is the order on the GPU.

**Scene data arrives as components.** Systems of the module in `KE_PHASE_UPDATE` turn mesh,
sprite and label components into handles of the service; the passes read those handles, the
camera component and the light components in the render phase.

**A pipeline is asked for, never waited for.** A pass asks the service for a pipeline each time
it draws; the first request returns a placeholder and the real one replaces it when compiled.

## The default pipeline

Created by the module in this order; each is a plugin with one factory header.

| pass | slot | reads | writes |
|---|---|---|---|
| clear (in the module) | 0 | | "backbuffer" |
| shadow | 1 | | "shadow_map", "shadow_depth" |
| cluster | 2 | | the "light_clusters" tag |
| gbuffer | 3 | | "gbuffer_albedo", "gbuffer_normal", "gbuffer_emissive", "depth" |
| deferred lighting | 4 | the gbuffer names, "depth", "light_clusters", and "shadow_map" when shadows are on | "hdr" |
| skybox | 5 | "depth" | "hdr" |
| forward | 6 | "shadow_map" | "hdr", "depth", and "hdr_opaque", its own copy of "hdr" |
| tonemap | 7 | "hdr" | "backbuffer" |
| ui | 8 | | "backbuffer" |

Opaque and alpha-masked surfaces go through gbuffer and deferred lighting; blended ones through
forward, which shades them itself.

## What the parts agree on without a contract

These are string literals and numbers in the plugins. No header declares them, so a pass added
by a host has to match them by reading the code.

- The resource names of the table above, and the buffer "shadow_lvp" and the bind group
  "cluster_lights" that the lighting passes import.
- The slot numbers of the table above.
- The layout of the per-frame uniform of each shading pass, between the Zig struct of the pass
  and the `frame` block of its shader.
- The name a shader is loaded by: the pass name for a pass, the material name followed by the
  pass name for a material.

## A feature that is off

Shadows, clustered lights and image-based light are never compiled out of a shader. A feature
that is off binds a neutral resource in its place (a white texture for the shadow map, a black
cube for the environment), so the shading passes have one shader each whatever the host
enables.
