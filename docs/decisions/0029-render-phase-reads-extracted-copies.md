# 0029. The render phase reads copies of query results, not live storage

Recorded: 2026-10-13. The decision is older than this record.

## Context
The render phase is dispatched without being awaited and outlives the tick that started it, so it
overlaps the next tick's sim phases, which write the ecs.
## Decision
After the sim phases, `runtimeExtractRenderState` copies the entity ids and every term's column of
each render system's queries into buffers the runtime owns. Render queries resolve to those copies.
The next tick joins the pending render task with `runtimeJoinPendingRender` before it extracts again.
## Consequences
Sim and render never touch the same memory at once. A render failure is reported by the next join
or by `flush_render`, so a caller must flush before destroying anything render uses. A render
system cannot change structure.
