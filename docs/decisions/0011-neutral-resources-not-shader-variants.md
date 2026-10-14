# 0011. A lighting feature that is off binds a neutral resource instead of compiling another shader

Recorded: 2026-10-13. The decision is older than this record.

## Context
Shadows, clustered lights and image-based light are optional. A host can disable shadows and
image-based light, and a scene may have no skybox or no point lights.
Two passes shade surfaces, deferred lighting and forward, and both call the same feature functions.

## Decision
The feature functions are called unconditionally. A feature that is off is expressed by the
resource the pass binds: a white texture for the shadow map, a black cube for the environment, a
zero count in every cluster. The neutral value makes the function return the neutral element of
its term, 1 for visibility and 0 for the additive terms.

## Consequences
Each shading pass has one shader whatever the host enables, so there is no shader variant per
combination of features.
A pass must always have a resource to bind, which is why the service owns a white texture and a
black default cubemap.
A host cannot remove the cost of a feature that is off by compiling it out; it pays the call.
