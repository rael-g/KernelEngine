# How does an authored material become something a pass can draw?

A material is a Slang file that says how a surface looks. It names no pass and declares no entry
point. The build binds it into each pass that consumes materials; at runtime a mesh points at a
material handle, and the pass turns the handle into a pipeline plus a bind group.

## What an author writes

One file in a materials directory, with exactly one `struct <Name> : IMaterial`
(`scripts/generate_material_wrapper.cs`, `FindMaterialStruct`: no struct or more than one is an error,
"one material per file, so the file name identifies it"). `IMaterial` has two methods
(`src/shaders/ke/surface.slang:48-51`):

- `vertex(inout VertexInfo v)`: perturb the object-space vertex.
- `fragment(inout SurfaceState s)`: fill the PBR surface (albedo, metallic, roughness, normal,
  emissive, ao, alpha) from the interpolated inputs.

The file imports `forward_common` to reach the **fixed engine material set**, descriptor set 1
(`src/shaders/forward_common.slang:26-45`): a uniform block `mat` with `base_color`, `metallic`,
`roughness`, `alpha_cutoff`, `ior` and `distortion_strength`, plus `albedo`, `tex_sampler` and
`normal_map`. A material cannot declare uniforms or textures of its own; every material reads this one
block. `standard.slang` is the engine default and shows the shape: sample the albedo and the normal map,
write the surface, and `discard` when `alpha < mat.alpha_cutoff` (`src/shaders/materials/standard.slang`).

## What the build makes of it

`Ctx.materialShaders` runs once per consuming pass (`build.zig:426-468`). For each pass it lists every
`*.slang` in the materials directories, generates a wrapper from the pass's template by substituting the
material's module name and struct name, and compiles the wrapper's vertex and fragment entry points
(`build.zig:857-905`). The two templates are:

| pass | template | fragment entry |
|---|---|---|
| gbuffer | `src/zig/render/gbuffer/shaders/gbuffer_material.slang.in` | `ke_gbuffer_fs`: encodes the surface into the G-buffer |
| forward | `src/zig/render/forward/shaders/forward_material.slang.in` | `ke_transparent_fs`: shades the surface inline |

Both templates' vertex entries call the same `ke_forward_vs` (`forward_common.slang:55-71`), and both
fragment functions call the same `ke_surface_from_vertex`, which builds the tangent-to-world basis,
seeds a default surface and lets the material fill it (`forward_common.slang:76-95`). Only what happens after the surface is built differs between passes.

The output is `<material>.<pass>.{vs,fs}.wgsl` in the shader directory the service loads from
(`build.zig:829-850`, `shader_loader.zig:9-17`, `:39`). The directories searched are the shared
`src/shaders/materials` and one example's `materials` directory (`build.zig:422-425`).

The shadow pass does not use materials: its own shader reads only the position and the model matrix
(`src/zig/render/shadow/shaders/shadow.slang`), so a `vertex()` perturbation is not seen by shadows.

## What exists at runtime

`create_material` registers one material and returns a handle
(`render_service.h:131-141`; `asset_upload.zig:179-250`):

- `key` is required and dedups: a key already cached returns the existing handle.
- `shader` is the authored material's name; null or empty selects `standard`, and a name of 64 bytes or
  more is refused (`asset_upload.zig:186-190`, `render_service.zig:32`).
- The base colour's rgb is converted from sRGB to linear; alpha is kept (`asset_upload.zig:198-201`).
- The MASK cutoff reaches the GPU only for MASK materials; every other mode uploads `0`
  (`asset_upload.zig:197`), which is why `standard.slang`'s `discard` never fires for them.
- A 48-byte uniform buffer and a bind group over the service's four-entry material layout are created;
  an absent albedo becomes the 1x1 white texture and an absent normal a 1x1 flat normal
  (`asset_upload.zig:203-225`, `render_service.zig:386-394`).
- An unknown handle resolves to the built-in white material (`render_service.zig:153-156`).

The mesh component's `alpha_mode` is `OPAQUE`, `MASK` or `BLEND` (`handles.h:29-34`) and the material
stores it. It decides the pass: `OPAQUE` and `MASK` go to the gbuffer pass and `BLEND` to the forward
pass ([render.md](render.md#opaque-and-transparent-surfaces-take-different-passes)).

## How a pass draws with it

For each draw a consuming pass:

1. Asks the service for the material's shader name (`material_shader`).
2. Loads `<name>.<pass>` as a vertex and a fragment module and writes them into its pipeline template
   (`gbuffer_module.zig:73-82`, `forward_module.zig:102-112`). If either file is missing the draw is
   skipped.
3. Asks the pipeline cache for the pipeline ([pipeline-cache.md](pipeline-cache.md)).
4. Binds the material's bind group at set 1 (`gbuffer_module.zig:152-154`, `forward_module.zig:264-266`)
   and the object's transform at set 2.

Everything about the pipeline except the two modules is fixed by the pass: vertex layout, blend state,
depth state and the other three bind group layouts.

## Where a mesh gets its material

A mesh component either carries a valid material handle, or the `render.mesh.resolve` system builds
one from the values authored on the mesh itself: colour, roughness, alpha mode, cutoff, `ior` and
`distortion_strength`, keyed by the hex bit patterns of all of those but `distortion_strength`, with
metallic fixed at `0` and the default shader (`mesh_resolve.zig:151-175`, run in `KE_PHASE_UPDATE`,
`render_module.zig:286-294`). A mesh authored in a scene therefore draws with `standard`.
The in-tree callers of `create_material` that exist outside that system pass no shader either
(`asset_resolver.zig:451-464`, `sprite_resolve.zig:74-86`); the way to pick an authored material is the
`shader` argument of `create_material`, which game code reaches through the render resources wrapper
(`examples/csharp/03_pbr_directional/Program.cs:43-44`).
