# 0013. An authored material names no pass; the build binds it to each consuming pass

Recorded: 2026-10-13. The decision is older than this record.

## Context
A material can be drawn by the gbuffer pass or by the forward pass. The two differ in what happens
after the surface is built: encoding into targets, or shading inline.

## Decision
A material file implements `IMaterial` and imports neither a pass nor declares an entry point. A
template per pass is the only place that knows how to bind an `IMaterial` into that pass, and the
build generates one wrapper for every material and every consuming pass.
One `IMaterial` struct per file is required, so the file name identifies the material.

## Consequences
Adding a material needs no change to a pass; adding a pass that consumes materials needs a template
and one more call of `Ctx.materialShaders`.
Every material is compiled once per pass, whether or not a mesh uses it with that pass.
A material cannot reach anything outside the fixed engine material set.
Shaders are found at runtime by `<material>.<pass>`, so a missing file is a skipped draw.
