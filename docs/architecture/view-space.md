# View space

This is a map: the parts that decide what a view or projection matrix looks like, and what each
hands on. How a part works inside is on the generated page of its file. Contracts are under
`src/c/view/` and `src/c/render/`, plugins under `src/zig/view/` and `src/zig/render/`.

## The parts

| part | contract | plugin | receives | hands on |
|---|---|---|---|---|
| device convention | `ke_ndc_convention` | webgpu, through `get_ndc_convention` of `ke_gpu_device` | nothing | the clip space the device expects |
| view space | `ke_view_space` | view/space, two factories `ke_view_space_rh_create` and `ke_view_space_lh_create` | the clip convention, per call | view and projection matrices, and `depth_from_view_z` |
| camera | `ke_render_camera` | camera | `ke_view_space`, a copy of the clip convention | matrices from a `ke_camera_component` and its world transform |
| pass | none | gbuffer, deferred lighting, forward, skybox, cluster, shadow | the camera, or the view space | its own use of the matrices |

## What ties the parts together

**Two questions, two contracts.** `ke_ndc_convention` answers what clip space the device expects:
`z_zero_to_one`, `y_flip` and `clip_left_handed`. `ke_view_space` answers which way the engine's
camera faces and what the matrices look like for that. Neither knows the other's choice; the
projection slots of `ke_view_space` take the convention as an argument.

**One implementation serves both handednesses.** The right-handed factory and the left-handed
one differ in the handedness stored in the state, and `depth_from_view_z` reports it as a sign, so
a consumer turns a view-space z into a positive depth without knowing which space it holds.

**The module chooses the view space.** `ke_render_module_create` takes an optional
`ke_view_space` and creates and owns a right-handed one when none is given. It refuses to be
created when the device reports `clip_left_handed` as 0. It then creates the `ke_render_camera`
over the view space and the device's convention and owns it.

**Passes take the camera; two also take the view space.** Gbuffer, deferred lighting and forward ask the camera
for `view` and `projection`. Skybox asks for `view_rotation` and `perspective_projection`.
Cluster asks for `view` and `perspective_frustum` and also takes the view space, for
`depth_from_view_z`. Shadow takes the view space and the convention and builds an orthographic
projection of its own from the directional light with `look_at` and `orthographic`.

**The camera component decides perspective or orthographic.** `projection` follows the
`orthographic` field of the component; `perspective_projection` and `perspective_frustum` always
describe a perspective camera. The field `fov` is in degrees on the component and in radians
on the view space.

**The user interface reads the convention directly.** The ui pass takes the device's convention
and reads `y_flip` for its own orthographic projection.

## What the parts agree on without a contract

- The sign of `depth_from_view_z`: the shading shaders and the cluster shaders multiply a
  view-space z by it, so every part that reads it must be handed it by the same view space that
  built the view matrix.
- A transform whose rotation terms are all near zero is not a rotation: the view space then aims
  the camera at the world origin.
- Only `z_zero_to_one` and `y_flip` are read by a matrix builder; `clip_left_handed` is read in
  one place, the check of `ke_render_module_create`.
