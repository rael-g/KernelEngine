# 0012. Refraction is a term only the forward pass has

Recorded: 2026-10-13. The decision is older than this record.

## Context
The shading vocabulary has four terms shared by both passes. Refraction needs the colour of
what lies behind a surface.
A deferred pass shades from a gbuffer that holds one surface per pixel, so there is nothing behind
a fragment to sample.

## Decision
`refraction_contribution` is called only by the forward pass. Forward copies the shaded frame
"hdr" into "hdr_opaque" before it draws, so the function samples a texture it does not write.
There is no neutral default for it, because it has no "off" state.

## Consequences
Only blended materials can refract; `ior` and `distortion_strength` are read for them alone.
The forward pass pays a full texture copy of the frame each time it has a camera.
Two sampling resources (binding 1 and 2 of set 0) exist for forward only.
