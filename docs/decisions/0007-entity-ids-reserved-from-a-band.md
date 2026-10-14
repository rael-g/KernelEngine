# 0007. Reserved entity ids come from a band the world never issues from

Recorded: 2026-10-13. The decision is older than this record.

## Context
`entity_reserve` must be callable from any wave thread, and the contract forbids implementing it by
forwarding to the single-threaded `entity_create`.
## Decision
The flecs plugin hands reserved ids out of `[reserve_low, world_id_base)` with one atomic
increment, and tells flecs to allocate only from `world_id_base` upward. A reserved id is a usable
reference at once; the entity enters the world at its first `component_add` or at
`entity_materialize`. A bitmap records which ids have had their one life.
## Consequences
The band is the pool's capacity: `entity_reserve` returns 0 once spent, and
`ke_ecs_flecs_params.world_id_base` sets it. A reserved entity destroyed later is not revived by a
later add.
