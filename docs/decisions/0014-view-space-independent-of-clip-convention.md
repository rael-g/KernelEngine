# 0014. View space and the device clip convention are two contracts

Recorded: 2026-10-13. The decision is older than this record.

## Context
Projection matrices depend on two unrelated facts: which way the engine's camera faces, and which
clip space the device expects (depth range, vertical flip, handedness of clip space).
Other parts, shading and cluster shaders, need a view-space z as a positive depth.

## Decision
`ke_view_space` owns the camera's facing and builds the matrices; `ke_ndc_convention` is data the
device reports and is passed to the projection slots as an argument. Neither knows the other's
choice. `ke_view_space_params.depth_from_view_z` gives consumers that cannot call the interface the
sign they need.

## Consequences
A right-handed and a left-handed view space run unchanged on any device.
A consumer that caches a matrix or the factor makes its own choice: no slot is documented as
constant.
`clip_left_handed` has no builder behind it, so the module refuses a device reporting it as 0.
