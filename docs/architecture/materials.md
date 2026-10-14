# How does an authored material become something a pass can draw?

This is a map: the parts between a material file and a draw, and what each hands on. How a part
works inside is on the generated page of its file. Shared shader modules are under
`src/shaders/`, the service under `src/zig/render/service/`.

## The parts

| part | where | receives | hands on |
|---|---|---|---|
| material file | a `.slang` file with one `IMaterial` struct | the fixed engine material set | a `vertex` and a `fragment` method |
| wrapper templates | `gbuffer_material.slang.in`, `forward_material.slang.in` | a material's module and struct name | the entry points `vs_main` and `fs_main` of one material for one pass |
| build | `Ctx.materialShaders` in the root `build.zig` | every material file, one template per consuming pass | compiled `<material>.<pass>` vertex and fragment shaders |
| service | `ke_render_service`, `create_material` | a key, colour, factors, textures, an alpha mode, a shader name | a material handle, its uniform and its bind group |
| mesh resolve | the system "render.mesh.resolve" of the module | a mesh component with no material handle | a handle made from the values authored on the mesh |
| pass | gbuffer, forward | a mesh component's material handle | a pipeline and a bind group per draw |

## What ties the parts together

**A material names no pass.** It implements `IMaterial` and reads one fixed set, the `mat`
block, `albedo`, `tex_sampler` and `normal_map` of `forward_common.slang`, at set 1. It cannot
declare uniforms or textures of its own. Exactly one `IMaterial` struct per file is required by
`scripts/generate_material_wrapper.cs`.

**The build binds a material to each consuming pass.** For every material file and every pass
that consumes materials, a wrapper is generated from the pass's template and compiled. Both
templates call `ke_forward_vs` for the vertex stage and build the surface with
`ke_surface_from_vertex`; the fragment stage then differs, `ke_gbuffer_fs` for gbuffer and
`ke_transparent_fs` for forward. The shadow pass uses no material.

**The material files searched are two directories.** `src/shaders/materials` and the
`materials` directory of one example, both listed in the root `build.zig`.

**The service owns the runtime side.** `create_material` is keyed and deduplicates. A null or
empty shader name selects the default material shader, and a name of `MAX_SHADER_NAME` bytes or
more is refused. The base colour is converted from sRGB to linear. The alpha cutoff reaches the
GPU only for `KE_ALPHA_MODE_MASK`. An absent albedo is the white texture and an absent normal map
a flat normal. A handle the service does not know resolves to its built-in white material.

**The alpha mode chooses the pass.** `ke_alpha_mode` is stored by the service. Gbuffer draws
every mesh whose material is not `KE_ALPHA_MODE_BLEND`, forward draws only those that are.

**A mesh gets its material from its own values or from a handle.** A mesh with no material
handle is given one by "render.mesh.resolve" in `KE_PHASE_UPDATE`, from its colour, roughness,
alpha mode, cutoff, `ior` and `distortion_strength`, with the default shader. A game picks an
authored material by passing `shader` to `create_material`.

**A pass draws a material in three steps.** It asks the service for the material's shader name
(`material_shader`), loads `<name>.<pass>` into its pipeline template, and asks the pipeline
cache for the pipeline; a draw whose shader is missing is skipped. It binds the material group
at set 1 and the object at set 2.

## What the parts agree on without a contract

- The default shader name "standard", in the service and in both passes.
- The shader file name `<material>.<pass>`, with the pass names "gbuffer" and "forward", between
  the build and the passes' `PASS_NAME`.
- The material layout: a uniform block, an albedo texture, a sampler and a normal texture, in
  that order, between `material_bgl` in the service and `forward_common.slang`.
- The 48-byte layout of the material uniform, between `createMaterial` in `asset_upload.zig` and
  the `Material` struct in `forward_common.slang`.
