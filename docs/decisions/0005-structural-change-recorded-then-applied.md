# 0005. A system body records structural changes and the runtime applies them after the wave

Recorded: 2026-10-13. The decision is older than this record.

## Context
Bodies of one wave run concurrently on workers. The ecs says its structural calls are
single-threaded, and component column pointers stay valid only until the next structural change.
## Decision
A body reaches component memory through `ke_system_ctx` and changes structure only through
`ke_ecs_commands`, which records into a queue owned by that body's call. `deferFlush` applies the
queues in package order after the wave's barrier. `ke_ecs_commands` has no immediate flavour; a
caller that needs an immediate change uses `ke_ecs` directly.
## Consequences
No body sees storage move under it, and nothing one body queued is visible to a sibling of the
same wave. A `spawn` returns its id at once (reserved) so the body can attach to it. The render
phase has no queue and every recording call fails with `not_supported`.
