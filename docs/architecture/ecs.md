# What does the ECS contract promise about threads and structural change, and how does the flecs plugin keep it?

This is a map: the parts around the ecs, what each receives and what it hands on. How a part works
inside is on the generated page of its file. The contract is `ke_ecs` in
`src/c/ecs/kernel_engine/ecs/ke_ecs.h`; its one implementation is
`src/zig/ecs/flecs/src/ecs_flecs.zig`, made by `ke_ecs_flecs_create`.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| ecs | `ke_ecs` | component registrations, structural calls, query registrations | entity ids, component bytes, segments of columns |
| flecs plugin | `ke_ecs_flecs_create`, `ke_ecs_flecs_params` | `world_id_base` | a `ke_ecs_handle` that owns the world |
| commands | `ke_ecs_commands` | recorded spawn, attach, detach, despawn, defer | the changes, applied by the runtime at the wave barrier |
| runtime | `ke_runtime_create` | the `ke_ecs` it borrows | queries resolved before a wave, structural calls after it |

**What may run at the same time is stated per slot in the header.** Entity creation and
destruction, `component_add`, `component_remove` and `entity_materialize` are structural and
single-threaded; `query_resolve` runs single-threaded before a parallel wave. `entity_reserve` is
the one entity operation callable from any wave thread.

**The runtime keeps those rules.** It resolves queries on the tick thread before dispatching a
wave, and applies the structural changes a body recorded in `ke_ecs_commands` only after the
wave's barrier. A body's `spawn` reserves its id with `entity_reserve`; the entity enters the
world at the barrier through `entity_materialize` or the first `component_add`.

**A query yields segments.** `query_resolve` writes one `ke_ecs_segment` per matching archetype:
the entities and one column per term, a tag's column being null. It reports the total number of
segments, which may exceed the capacity the caller gave.

**A component is its name.** `component_register` returns the same id for a repeated name, which
must describe the same layout; a `ke_component_field` table, when given, is compared field by
field and must outlive the ecs.

**The flecs plugin keeps two id sources apart.** Ids below `world_id_base` form the pool
`entity_reserve` draws from; the world's own allocator issues ids from `world_id_base` upward.
`ke_ecs_flecs_params.world_id_base` is therefore the capacity of the pool.

**An internal flecs failure ends the process.** The plugin replaces the flecs abort hook,
process-wide, and ends through `ke_error_fatal`; every other failure is a `ke_error` and a
sentinel return.

## What the parts agree on without a contract

- The invalid entity is `KE_ENTITY_INVALID` (0), and the plugin also treats component id 0 as
  invalid, while `KE_COMPONENT_INVALID` is declared as the all-ones value.
- A destroyed or never-materialized id is refused by the plugin: add and get return null, destroy
  and remove do nothing. The contract does not say this.
