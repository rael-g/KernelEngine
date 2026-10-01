# How do lights, shadows and image-based light reach a shading pass?

Two passes shade a surface: `deferred_lighting` for every opaque and alpha-masked material, and
`forward` for every blended one ([render.md](render.md#opaque-and-transparent-surfaces-take-different-passes)).
They do not share code at the pass level. They share a **vocabulary of plain shader functions**, each
reading a resource that has a neutral value when the feature behind it is absent, so a pass calls
every function unconditionally and a missing feature contributes nothing.

| function | file | reads | neutral value when the feature is off |
|---|---|---|---|
| `sample_shadow_visibility` | `src/shaders/shadow_feature.slang:30` | set 0 bindings 4 to 6 | a 1x1 white texture: returns 1.0 |
| `ibl_contribution` | `src/shaders/ibl_feature.slang:23` | set 0 bindings 7 and 8 | the black default cubemap: returns 0 |
| `accumulate_clustered_lights` | `src/shaders/cluster_feature.slang:99` | set 3 bindings 0 to 6 | a zero light count in every cluster: returns 0 |
| `pbr_direct` | `src/shaders/ke/pbr.slang:35` | none, pure math | not applicable |

`deferred_lighting.slang:89-99` and `transparent_forward.slang:54-64` make the same calls in the
same order; the forward pass adds a fourth, `refraction_contribution`, which only it can have
(`refraction_feature.slang`, called at `transparent_forward.slang:74`). It reads the
`hdr_opaque` copy of the frame, and an opaque surface shaded from a G-buffer has no "behind" to
sample. `cluster_feature.slang` keeps its own copy of the direct-lighting BRDF
(`cluster_pbr_direct`, `cluster_feature.slang:64`) instead of importing `ke.pbr`.

## How the feature is "off"

The choice is made by which resource the pass binds, not by compiling a different shader.

- **Shadows.** `ke_render_feature_params.enable_shadows` (`render_module_create.h`) decides whether the
  shadow module declares the `shadow_map` resource and registers its system
  (`shadow_module.zig:156-158`, `:279`). A shading pass asks the service for `shadow_map` and falls
  back to the white texture when none was declared
  (`deferred_lighting_module.zig:81-82`, `forward_module.zig:148-149`). The `shadow_lvp` uniform is
  published whether or not shadows are enabled (`shadow_module.zig:152-154`).
- **IBL.** `enable_ibl` false binds the black default cubemap at binding 7; true binds the cubemap of
  the first `ke_skybox_component`, and a frame with no skybox component resolves the none-handle to
  the same black cubemap (`deferred_lighting_module.zig:85`, `:136-143`;
  `asset_upload.zig:160-165`). The skybox pass reads the same cubemap for the background.
- **Dynamic lights.** The cull pass always runs and always writes its per-cluster counts; with no
  point or spot lights every count is zero.

A pass rebuilds its frame bind group when the skybox cubemap changes (`deferred_lighting_module.zig:141-144`).

## Which light components are read

| component | which entities | where it is read |
|---|---|---|
| directional light | the first one only | shading passes and the shadow pass (`deferred_lighting_module.zig:159-167`, `shadow_module.zig:76-82`) |
| ambient light | the first one only; overrides the ambient field of the directional light | `deferred_lighting_module.zig:168-173` |
| point, spot light | every one, up to the cull pass's cap | `cluster_module.zig:109-176` |

The directional light's contribution is gated by `frame.shadow_params.z`, which the pass sets to `1`
when a directional light exists (`deferred_lighting_module.zig:166`; read at
`deferred_lighting.slang:89`). The name does not mean "shadows are on".

Point and spot lights cast no shadows: they reach a surface only through
`accumulate_clustered_lights`, and the shadow pass queries the directional light and the meshes
(`shadow_module.zig:243-248`).

## The single directional shadow map

The shadow system runs in command slot 1 and renders every mesh from the directional light's point
of view into two attachments, an `RGBA16_FLOAT` map holding the depth in its red channel and a
`D32_FLOAT` depth buffer (`shadow_module.zig:158-178`, `shadow.slang:28-38`). The light's view and
projection come from the view space ([view-space.md](view-space.md#the-directional-lights-view)).

`ke_render_shadow_params` carries `resolution`, `light_distance`, `extent`, `near_plane` and
`far_plane`; a zero field falls back to 1024, 25, 20, 0.1 and 50 (`shadow_module.zig:13-30`). Unset
means zero, so a caller can name only what it changes.

The lookup is one tap (`shadow_feature.slang:30-38`): project the world position by `lightVP`, return
`1.0` when the result lies outside the unit cube, otherwise compare the depth with the stored one
under a bias of `0.005` and return `0.3` when occluded. A shadowed surface therefore keeps 30% of the
directional light's direct term, and the term is the only one scaled: ambient, cluster lights and IBL
are not.

## The cluster cull

A compute pass divides the view frustum into a grid of `grid_x * grid_y * grid_z` clusters and records,
for each, which point and spot lights touch it. `ke_render_cluster_params` sets the grid and
`max_lights_per_cluster`; zero fields fall back to 32 x 18 x 24 and 256
(`render_module.zig:14-17`, `:199-209`).

Each frame the system (`cluster_module.zig:104-211`):

1. Copies every point and spot light into storage buffers, 1024 at a time, from the lights'
   components and world transforms (`UPLOAD_CHUNK`, `cluster_module.zig:11`). Each buffer holds at most
   `MAX_LIGHTS` = 1,000,000 entries; past that, further lights are dropped and a warning is logged once
   per kind (`cluster_module.zig:10`, `:137-140`, `:173-176`).
2. Reads the first camera and uploads `tan(fov / 2)`, the aspect, near, far, the view matrix and
   `depth_from_view_z` (`cluster_module.zig:192-200`).
3. Records one dispatch of `ceil(num_clusters / 64)` workgroups (`cluster_module.zig:204-208`).

One thread handles one cluster (`cluster_cull.slang:36-44`). It derives the cluster's slice
boundaries exponentially, `near * (far / near)^(iz / numZ)`, builds the view-space box of the cluster's
eight corners from the camera's field of view, then tests each light's bounding sphere against that
box and appends the light's index while the cluster has room
(`cluster_cull.slang:60-79`, `:85-107`). The shader never assumes the camera's facing: it multiplies
the view-space z by `depth_from_view_z`.

The shading side finds its cluster from the fragment: tile from `SV_Position.xy` over the viewport,
slice from `log(depth / near) / log(far / near)` with `depth = view_z * depth_from_view_z`
(`cluster_feature.slang:85-97`), then loops over that cluster's list. A point light's falloff is
`(1 - d / radius)^2` clamped; a spot light adds a linear ramp between the cosines of its outer and inner
angles (`cluster_feature.slang:105-136`).

The cull's results reach the shading passes through the bind group the cull pass imports under the
name `cluster_lights` at set 3, with the layout alongside it (`cluster_module.zig:307`); the cull
pass writes the `light_clusters` tag and the shading passes read it, which is what orders them.

## Where each resource is bound

The shading passes agree on binding numbers by convention; nothing enforces them
(a pipeline takes at most four bind group layouts, so there is no fifth set: `gpu_device.h:194`).

| set | binding | holds |
|---|---|---|
| 0 | 0 | per-frame uniform: camera position, directional light, ambient, viewport, view matrix (deferred also the inverse view-projection) |
| 0 | 1, 2 | forward only: the `hdr_opaque` copy and its sampler |
| 0 | 4, 5, 6 | the `shadow_lvp` uniform, shadow map, sampler |
| 0 | 7, 8 | the environment cubemap and its sampler |
| 1 | per pass | deferred: the four G-buffer textures; forward: the material |
| 2 | 0 | per-object transform (forward); an empty group (deferred) |
| 3 | 0 to 6 | cluster lights, indices, counts, grid uniform |

The deferred pass reads the G-buffer by exact texel and reconstructs the world position by pushing
`(ndc, depth, 1)` through the inverse view-projection; a texel whose depth is still the clear value is
discarded and left to the skybox (`deferred_lighting.slang:59-70`).

## What IBL does

The environment cubemap is sampled directly, with no prefiltering: the specular term samples it along
the reflection vector and scales by a Schlick fresnel; the diffuse term samples it along the normal,
scaled by albedo and `(1 - metallic) * (1 - F)` (`ibl_feature.slang:23-28`).
