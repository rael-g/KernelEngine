# How does the engine build view and projection matrices for the device's clip space?

Two contracts answer two different questions, and a projection is built from both:

- `ke_ndc_convention` answers "what clip space does the **device** expect?" It is data the GPU
  device reports.
- `ke_view_space` answers "which way does the **engine's camera** face, and what do the matrices
  look like for that?" It is an interface a plugin implements.

Neither contract knows the other's choice. The projection builders take the device's convention as
an argument.

## What the device reports

`ke_ndc_convention` has three flags (`src/c/render/kernel_engine/render/gpu/ndc_convention.h:11-16`):

| field | meaning |
|---|---|
| `z_zero_to_one` | clip z in `[0,1]` (WebGPU) rather than `[-1,1]` (GL) |
| `y_flip` | the framebuffer origin is top-left and the projection must negate its y row |
| `clip_left_handed` | the clip space is left-handed |

A device returns it from `get_ndc_convention` (`gpu_device.h:336`). The WebGPU backend answers
`z_zero_to_one = 1`, `y_flip = 0`, `clip_left_handed = 1` (`gpu_device_webgpu.zig:709-711`), and the
render service stores the answer when it is created (`render_service.zig:273`).

Only two of the three flags have a reader. `z_zero_to_one` picks the depth-range variant of the
builder and `y_flip` negates the y row (`view_space.zig:113-117`, `:134`, `:160`); the UI pass reads
`y_flip` for its own orthographic projection (`ui_module.zig:297`). `clip_left_handed` is read in one
place: the render module refuses to be created when the device reports it as `0`
(`render_module.zig:253`). No projection builder branches on it.

## What `ke_view_space` offers

The interface (`src/c/view/kernel_engine/view/view_space.h`) is a vtable with six working slots and `destroy`:

| slot | what it returns |
|---|---|
| `params` | `ke_view_space_params`, whose one field `depth_from_view_z` multiplies a view-space z into a distance in front of the camera |
| `look_to`, `look_at` | world-to-view for an eye plus a direction or a target |
| `view_from_transform` | world-to-view for a camera placed by a world transform |
| `perspective(fov_y, aspect, near, far, clip, out)` | perspective projection, `fov_y` in radians |
| `orthographic(width, height, near, far, clip, out)` | orthographic projection |

The header states that no slot's result is documented as constant and that a consumer which caches
one is making its own choice (`view_space.h:27-32`).

### Two plugins, one implementation

`src/zig/view/space` builds one library, `ke_view_space` (`build.zig:298`), with two factories,
`ke_view_space_rh_create` and `ke_view_space_lh_create` (`view_space.zig:196-206`; headers
`view_space_rh_create.h`, `view_space_lh_create.h`). They differ in a single `Handedness` value held
in the state (`view_space.zig:13-18`), and every slot switches on it:

- **Facing.** The right-handed space looks down `-z`, the left-handed one down `+z`. `params` reports
  that as `depth_from_view_z` = `-1` or `+1` (`view_space.zig:33-40`), so a consumer can turn a
  view-space z into a positive depth without knowing which space it holds.
- **View from a transform.** The rotation basis of the camera's world matrix gives its local axes;
  the camera faces along local `+z` negated in the right-handed space and along local `+z` in the
  left-handed one (`view_space.zig:101-110`). A matrix whose off-diagonal rotation terms are all
  near zero is treated as carrying no rotation and the camera aims at the world origin
  (`view_space.zig:89-99`).
- **Projection.** The builder is the matching zmath variant: `perspectiveFovRh` or `perspectiveFovLh`
  for `z_zero_to_one`, the `...Gl` variant otherwise, and likewise for the orthographic builders
  (`view_space.zig:132-141`, `:161-170`). `y_flip` then negates the y row (`view_space.zig:113-117`).

The tests pin the shared guarantee: a surface in front of the camera has positive
`depth_from_view_z * z` in both spaces and the far point is deeper than the near one
(`view_space.zig:222-237`).

### Which one the engine uses

The render module takes an optional `ke_view_space` as a parameter; when none is supplied it creates
the right-handed one and owns it (`render_module.zig:242-246`). The shadow, cluster, gbuffer,
deferred-lighting, skybox and forward passes receive that one pointer, and every one of them except
the cluster pass also receives the device's convention (`render_module.zig:304-342`).

## How a camera component becomes a projection

`Camera(c).projection` (`src/zig/render/common/camera.zig:5-20`) is a Zig source shared by the passes
over a `ke_camera_component` (`components.h:15-25`):

- `orthographic != 0`: the visible height is `orthographic_size * 2`, the width is that times the
  aspect, and `view_space->orthographic` builds the matrix with the component's near and far
  planes (`camera.zig:12-16`).
- Otherwise: `fov` is read **in degrees**, converted to radians, and handed to
  `view_space->perspective` (`camera.zig:18-19`).

The component defaults are `fov` 60, `near_plane` 0.1, `far_plane` 1000, `orthographic_size` 5
(`components.h:15-20`, `component_fields.h:19`).

The gbuffer, deferred-lighting and forward passes all call it
(`gbuffer_module.zig:126`, `deferred_lighting_module.zig:130`, `forward_module.zig:200`), each
building its view with `view_from_transform` (`gbuffer_module.zig:89-93` and the same three-line
helper in the other passes). Three passes do not use it:

- the skybox pass always builds a perspective projection from `fov`, whatever `orthographic` says,
  and zeroes the view's translation (`skybox_module.zig:70-77`);
- the cluster pass does not build a projection at all; it uploads `tan(fov / 2)`, the aspect, near
  and far (`cluster_module.zig:196`);
- the shadow pass builds an orthographic projection of its own, below.

## The directional light's view

The shadow pass places an eye `light_distance` units back along the light's direction from the world
origin, looks at the origin with `look_at`, and builds a square `orthographic(extent, extent, near,
far)` in the device's clip (`shadow_module.zig:59-74`). The up vector switches to `+z` when the
light is within about 8 degrees of vertical (`shadow_module.zig:64-67`).
