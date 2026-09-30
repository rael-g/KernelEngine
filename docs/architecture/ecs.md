# What does the ECS contract promise about threads and structural change, and how does the flecs plugin keep it?

The contract is `ke_ecs` (`src/c/ecs/kernel_engine/ecs/ke_ecs.h:32`). Its one implementation is
`src/zig/ecs/flecs/src/ecs_flecs.zig`, created by `ke_ecs_flecs_create`
(`ecs_flecs.zig:532`).

## Identity

An entity is a `uint64_t`; `0` is invalid (`src/c/ecs/kernel_engine/ecs/ecs.h:13-14`). A component
id is a `uint32_t` (`ecs.h:16`), assigned by `component_register`. A component registers under a
**name**; a repeated name returns the same id and must describe the same layout
(`ke_ecs.h:42-58`). A size of `0` registers a tag, which has no storage.

When a field table is passed, two registrations are compared field by field; without one, only the
size is compared (`ke_ecs.h:45-48`). A table that describes bytes past the component's size is
refused (`ecs_flecs.zig:283`), as is a size that differs from the first registration
(`ecs_flecs.zig:297`).

When a component is first attached to an entity, the plugin seeds the defaults the field table
declares (`ecs_flecs.zig:402-408`); fields with no declared default stay zero.

## What may run at the same time

Each slot states its own rule in the header:

| slot | rule |
|---|---|
| `entity_create`, `entity_destroy`, `component_add`, `component_remove`, `entity_materialize` | structural; single-threaded (`ke_ecs.h:36`, `39`, `80`, `86`, `137-139`) |
| `query_resolve` | single-threaded, before a parallel wave (`ke_ecs.h:109-111`) |
| `entity_reserve` | **callable concurrently from any wave thread — the only entity operation that is** (`ke_ecs.h:123-127`) |

The runtime honours the first two by resolving queries on the tick thread before dispatching a
wave, and by applying a wave's structural changes only after its barrier
([runtime.md](runtime.md#structural-change--the-defer-queue)).

## Queries

A query is a tuple of component ids, at most `KE_QUERY_MAX_TERMS` (8) long
(`ke_ecs.h:16`; refused past it at `ecs_flecs.zig:440`). `query_resolve` fills an array of
**segments**, one per archetype the query matches. A segment is the matched entities plus one column
pointer per term, in registration order, all aligned with the entity array; a tag's column is
`NULL` (`ke_ecs.h:18-29`; `ecs_flecs.zig:501`). Column pointers are plain memory that stays valid
until the next structural change (`ke_ecs.h:22`).

`query_resolve` stops filling at `max_segments` and reports how many it wrote; a caller whose
array is smaller than the match count does not learn that (`ecs_flecs.zig:493-496`).

## Reserving an id from a parallel body — how the plugin meets the contract

flecs' own id allocator walks a shared entity index, which is not safe under concurrent calls
(`ecs_flecs.zig:209-214`). `entity_reserve` therefore never asks flecs. It hands out ids from a
band the world is configured never to issue from:

- the band is `[reserve_low, world_id_base)`, where `reserve_low` is one past the largest id flecs
  had issued when the world was created (`ecs_flecs.zig:574`);
- flecs is told to allocate only from `world_id_base` upward, by an entity range
  (`ecs_flecs.zig:581`);
- a reserve is one atomic increment of a counter (`ecs_flecs.zig:215-222`).

The reserved id is a usable reference at once, but the entity does not exist in the world until
something materializes it: the first `component_add` for it does (`ecs_flecs.zig:395`), and
`entity_materialize` does so for an entity that never gets a component (`ecs_flecs.zig:229-251`). A
bitmap records which ids have already been given their one life, because flecs cannot answer that
(`ecs_flecs.zig:87-91`).

**The band is the pool's capacity**: `entity_reserve` returns `0` once it is spent
(`ecs_flecs.zig:220`). Its size is `ke_ecs_flecs_params.world_id_base`, default `1 << 20`
(`src/zig/ecs/flecs/include/kernel_engine/ecs/ke_ecs_flecs.h:28-32`; `ecs_flecs.zig:78`).

## What a flecs internal failure does

flecs reports its own assertion failures by calling an abort hook. The plugin replaces that hook,
process-wide, so the last captured flecs message is printed and the process ends through
`ke_error_fatal`; the world cannot be recovered past an internal assertion
(`ecs_flecs.zig:27-50`; `ke_ecs_flecs.h:35-42`). This is the one place in the engine where a
library's failure is turned into process exit rather than a returned `ke_error`.
