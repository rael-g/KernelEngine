# What does the ECS contract promise about threads and structural change, and how does the flecs plugin keep it?

The contract is `ke_ecs` (`src/c/ecs/kernel_engine/ecs/ke_ecs.h:32`). Its one implementation is
`src/zig/ecs/flecs/src/ecs_flecs.zig`, created by `ke_ecs_flecs_create`
(`ecs_flecs.zig:505`).

## Identity

An entity is a `uint64_t`; `0` is invalid (`src/c/ecs/kernel_engine/ecs/ecs.h:13-14`). A component
id is a `uint32_t` (`ecs.h:16`), assigned by `component_register`. A component registers under a
**name**; a repeated name returns the same id and must describe the same layout
(`ke_ecs.h:42-58`). A size of `0` registers a tag, which has no storage.

When a field table is passed, two registrations are compared field by field; without one, only the
size is compared (`ke_ecs.h:45-48`). A table that describes bytes past the component's size is
refused (`ecs_flecs.zig:255`), as is a size that differs from the first registration
(`ecs_flecs.zig:269`).

The first table a name is registered with is the one later registrations are compared to: the plugin
records it (`rememberLayout`, `ecs_flecs.zig:155-170`; test `:725`), keeping the pointer rather than
a copy, which is why the header requires the table to outlive the ecs (`ke_ecs.h:52-53`). Two tables
differ when any field's type, offset, size or name differs, or when their lengths differ
(`firstLayoutDiff`, `:146-153`). A conflict fails the call: `component_register` returns `0` and the
error names the index of the first field that disagrees (`:304-312`; `ke_ecs.h:56-58`). A
registrant that passes no table joins a name that has one, on size alone (`:714`).

When a component is first attached to an entity, the plugin seeds the defaults the field table
declares (`ecs_flecs.zig:374-380`); fields with no declared default stay zero.

### A stale id is refused

An entity id is flecs's own: the low 32 bits are an index, the high 32 a liveness counter that grows
when the index is recycled (`flecs.h` `ecs_entity_t`, `build/vcpkg-installed/<triplet>/include/flecs.h:380-385`).
An id whose entity was destroyed is therefore not alive even after its index is reused. The contract
does not say what a stale id does; the plugin asks `ecs_is_alive` first and, for a dead id,
`entity_destroy` and `component_remove` return without effect, and `component_add` and
`component_get` return `NULL` (`ecs_flecs.zig:229`, `:396`, `:416`, `:424`). A reserved id has no
counter, so the plugin records separately that it has been given its one life: a reserved entity that
was destroyed is not revived by a later `component_add` (`ecs_flecs.zig:79`; test `:930`).

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
(`ke_ecs.h:16`; refused past it at `ecs_flecs.zig:412`). `query_resolve` fills an array of
**segments**, one per archetype the query matches. A segment is the matched entities plus one column
pointer per term, in registration order, all aligned with the entity array; a tag's column is
`NULL` (`ke_ecs.h:18-29`; `ecs_flecs.zig:473`). Column pointers are plain memory that stays valid
until the next structural change (`ke_ecs.h:22`).

`query_resolve` stops filling at `max_segments` and reports how many it wrote; a caller whose
array is smaller than the match count does not learn that (`ecs_flecs.zig:465-468`).

## Reserving an id from a parallel body — how the plugin meets the contract

The contract forbids satisfying `entity_reserve` by forwarding to `entity_create`
(`ke_ecs.h:129-131`), and `entityReserve` never calls into the flecs world (`ecs_flecs.zig:192-199`).
It hands out ids from a band the world is configured never to issue from:

- the band is `[reserve_low, world_id_base)`, where `reserve_low` is one past the largest id flecs
  had issued when the world was created (`ecs_flecs.zig:547`);
- flecs is told to allocate only from `world_id_base` upward, by an entity range
  (`ecs_flecs.zig:554`);
- a reserve is one atomic increment of a counter (`ecs_flecs.zig:192-199`).

The reserved id is a usable reference at once, but the entity does not exist in the world until
something materializes it: the first `component_add` for it does (`ecs_flecs.zig:367`), and
`entity_materialize` does so for an entity that never gets a component (`ecs_flecs.zig:201-223`). A
bitmap records which ids have already been given their one life, because flecs cannot answer that
(`ecs_flecs.zig:79`).

**The band is the pool's capacity**: `entity_reserve` returns `0` once it is spent
(`ecs_flecs.zig:197`). Its size is `ke_ecs_flecs_params.world_id_base`, default `1 << 20`
(`src/zig/ecs/flecs/include/kernel_engine/ecs/ke_ecs_flecs.h:28-32`; `ecs_flecs.zig:70`).

## What a flecs internal failure does

flecs reports its own assertion failures by calling an abort hook. The plugin replaces that hook,
process-wide, so the last captured flecs message is printed and the process ends through
`ke_error_fatal`; the world cannot be recovered past an internal assertion
(`ecs_flecs.zig:28-51`; `ke_ecs_flecs.h:35-42`). This is the one place in the engine where a
library's failure is turned into process exit rather than a returned `ke_error`.
