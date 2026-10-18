# Lighting

This is a map: the parts that produce light data, what each hands on, and the two passes that
consume it. How a part works inside is on the generated page of its file. Plugins are under
`src/zig/render/`, shared shader modules under `src/shaders/`.

## The parts

| part | plugin | receives | hands on |
|---|---|---|---|
| shadow | shadow | the directional light, meshes with a world transform, `ke_view_space`, `ke_render_shadow_params` | the target "shadow_map" and the buffer "shadow_lvp" |
| cluster | cluster | point and spot lights, the camera, `ke_view_space` | the bind group "cluster_lights" and the tag "light_clusters" |
| skybox | skybox | the `ke_skybox_component`, "depth" | the background, drawn into "hdr" |
| deferred lighting | deferred_lighting | the gbuffer targets, "depth", the three hand-offs above, the directional and ambient lights | "hdr" |
| forward | forward | blended meshes, "hdr", the three hand-offs above, the lights | "hdr_opaque" for its own sampling, and "hdr" |

Deferred lighting shades every opaque and alpha-masked surface, forward every blended one. They
share no code at the pass level; they share a vocabulary of shader functions.

## What ties the parts together

**Shading is a vocabulary of plain shader functions.** `sample_shadow_visibility`
(`shadow_feature.slang`), `ibl_contribution` (`ibl_feature.slang`), `accumulate_clustered_lights`
(`cluster_feature.slang`) and `pbr_direct` (`ke/pbr.slang`) are called by both shading passes in
the same order. Forward alone also calls `refraction_contribution`
(`refraction_feature.slang`), because only it has a copy of the frame behind the surface.

**A feature that is off is a neutral resource, not another shader.** The shadow function reads a
white texture when no "shadow_map" exists, the environment is a black cube when image-based light
is disabled or no skybox exists, and a cluster with no lights has a zero count. A host without
shadows creates no shadow pass and gives the shading passes no shadow group; `ibl_enabled` of
`ke_render_deferred_lighting_params` and `ke_render_forward_params` turns image-based light off.

**The directional light and the ambient light are the first of their kind.** Both shading passes
and the shadow pass read only the first directional light; the first ambient light replaces the
ambient field of the directional one. Point and spot lights reach a surface only through the
clusters and cast no shadow.

**Clusters are ordered before shading by their access lists.** The cluster pass writes the tag
"light_clusters" and imports the bind group "cluster_lights"; the shading passes read the tag
and bind the group, so the runtime runs them in that order.

**The view space is the only thing that knows which way the camera faces.** The cluster pass and
the shadow pass take `ke_view_space`; the cluster pass hands its `depth_from_view_z` on to the
shading shaders in the grid uniform.

## What the parts agree on without a contract

These are string literals and numbers in the plugins. No header declares them.

- The names "shadow_map", "shadow_depth", "shadow_lvp", "light_clusters", "cluster_lights",
  "hdr", "hdr_opaque" and "depth".
- The bind group sets of the shading passes. Set 0 is the per-frame uniform at binding 0, the
  shadow buffer, map and sampler at 4 to 6 and the environment cube and sampler at 7 and 8;
  forward alone also has the "hdr_opaque" copy and sampler at 1 and 2. Set 1 is the gbuffer
  (deferred) or the material (forward). Set 2 is empty (deferred) or the object (forward). Set 3
  is "cluster_lights", bindings 0 to 6. A pipeline takes four layouts, so there is no fifth set.
- The layout of the per-frame uniform of each shading pass, between its Zig struct and the
  `frame` block of its shader.
- The cluster grid uniform and the cull parameters, between `ClusterGridUniform` and
  `ClusterParams` in `cluster_module.zig` and the cluster shaders.
- The cull shader workgroup size, which the cluster pass repeats when it dispatches.
