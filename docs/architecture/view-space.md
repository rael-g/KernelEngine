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
`z_zero_to_one = 1`, `y_flip = 0`, `clip_left_handed = 1` (`gpu_device_webgpu.zig:712-714`), and the
render service stores the answer when it is created (`render_service.zig:275`).

Only two of the three flags have a reader. `z_zero_to_one` picks the depth-range variant of the
builder and `y_flip` negates the y row (`view_space.zig:113-117`, `:134`, `:160`); the UI pass reads
`y_flip` for its own orthographic projection (`ui_module.zig:298`). `clip_left_handed` is read in one
place: the render module refuses to be created when the device reports it as `0`
(`render_module.zig:258`). No projection builder branches on it.

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
`ke_view_space_rh_create` and `ke_view_space_lh_create` (`view_space.zig:198-208`; headers
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
(`view_space.zig:224-239`).

### Which one the engine uses

The render module takes an optional `ke_view_space` as a parameter; when none is supplied it creates
the right-handed one and owns it (`render_module.zig:247-251`). The shadow and cluster passes receive
that one pointer; the shadow pass also receives the device's convention (`render_module.zig:316-325`).
The gbuffer, deferred-lighting, skybox and forward passes receive the `ke_render_camera` the module
builds over it instead (`render_module.zig:265`, below).

## How a camera component becomes matrices

`ke_render_camera` (`src/c/render/kernel_engine/render/camera.h`) is the contract for what a
`ke_camera_component` (`components.h:15-25`) and its world transform mean as matrices. Its one
implementation is `src/zig/render/camera/`, created by `ke_render_camera_create` over a `ke_view_space`
and a copy of the device's clip convention (`render_camera.zig:108`). `render_module` creates it after the
view space and owns it (`render_module.zig:265`); the passes receive the pointer from their own
factories and never see the view space or the clip convention for this purpose.

The slots, in `camera.h` order (`render_camera.zig:25-100`):

- `view` is the view space's `view_from_transform` of the camera's world transform.
- `view_rotation` is the same view with its translation zeroed, for what is drawn infinitely far away.
- `projection` reads `orthographic`. When it is non-zero the visible height is `orthographic_size * 2`,
  the width is that times the aspect, and `view_space->orthographic` builds the matrix with the
  component's near and far planes (`render_camera.zig:65-70`). Otherwise `fov` is read **in degrees**,
  converted to radians, and handed to `view_space->perspective` (`render_camera.zig:49-53`).
- `perspective_projection` takes the perspective branch whatever `orthographic` says.
- `perspective_frustum` reports the tangent of half the vertical field of view, the aspect, near and far
  (`render_camera.zig:94`), again whatever `orthographic` says.

The component defaults are `fov` 60, `near_plane` 0.1, `far_plane` 1000, `orthographic_size` 5
(`components.h:15-20`, `component_fields.h:19`).

Which pass asks for what:

- gbuffer, deferred-lighting and forward ask for `view` and `projection`
  (`gbuffer_module.zig:118-120`, `deferred_lighting_module.zig:122-124`, `forward_module.zig:192-194`).
  Deferred lighting reconstructs positions from the depth the gbuffer wrote, so the two must agree, and
  asking the same interface is what makes them agree.
- the skybox pass asks for `view_rotation` and `perspective_projection`
  (`skybox_module.zig:59-61`), so an orthographic camera still gets a perspective sky.
- the cluster pass asks for `view` and `perspective_frustum` (`cluster_module.zig:190-192`), so it too
  describes a perspective camera whatever `orthographic` says; it still takes the view space for
  `depth_from_view_z`.
- the shadow pass builds an orthographic projection of its own from the light, below.

## The directional light's view

The shadow pass places an eye `light_distance` units back along the light's direction from the world
origin, looks at the origin with `look_at`, and builds a square `orthographic(extent, extent, near,
far)` in the device's clip (`shadow_module.zig:60-75`). The up vector switches to `+z` when the
light is within about 8 degrees of vertical (`shadow_module.zig:65-68`).
