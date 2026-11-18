# ECS

This is a map: the parts around the ecs, what each receives and what it hands on. How a part works
inside is on the generated page of its file. The contract is `ke_ecs` in
`src/c/ecs/kernel_engine/ecs/ke_ecs.h`; its one implementation is
`src/zig/ecs/flecs/src/ecs_flecs.zig`, made by `ke_ecs_flecs_create`.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| ecs | `ke_ecs` | component registrations, structural calls, query registrations | entity ids, component bytes, segments of columns |
| flecs plugin | `ke_ecs_flecs_create` | the setting `reserved_id_capacity` | a `ke_ecs_handle` that owns the world |
| commands | `ke_ecs_commands` | recorded spawn, attach, detach, despawn, defer | the changes, applied by the schedule after the bodies that recorded them |
| schedule | `ke_schedule_create` | the `ke_ecs` it borrows | queries resolved before the bodies run, structural calls after them |

**What may run at the same time is stated per slot in the header.** Entity creation and
destruction, `component_add`, `component_remove` and `entity_materialize` are structural and
single-threaded; `query_resolve` runs single-threaded before bodies run in parallel. `entity_reserve` is
the one entity operation callable from any body.

**The schedule keeps those rules.** It resolves queries on the ticking thread before running the
bodies as jobs, and applies the structural changes a body recorded in `ke_ecs_commands` only after
the bodies have run. A body's `spawn` reserves its id with `entity_reserve`; the entity enters the
world at the barrier through `entity_materialize` or the first `component_add`.

**A query yields segments.** `query_resolve` writes one `ke_ecs_segment` per matching archetype:
the entities and one column per term, a tag's column being null. It reports the total number of
segments, which may exceed the capacity the caller gave.

**A component is its name.** `component_register` returns the same id for a repeated name, which
must describe the same layout; a `ke_component_field` table, when given, is compared field by
field and must outlive the ecs.

**The flecs plugin keeps two id sources apart.** Ids below the `reserved_id_capacity` setting
form the pool `entity_reserve` draws from; the world's own allocator issues ids from that value
upward.

**A check flecs fails is a `ke_result`.** The triplets build flecs with soft checks kept in every
build type (`vcpkg-triplets/flecs-checks.cmake`), so a check of a caller's input logs and returns
instead of aborting, in release builds too. The plugin's log hook marks the calling
thread's call as refused, and the slot returns `KE_RESULT_INVALID_ARGUMENT` with flecs's message
logged. Only an internal flecs failure still ends the process, because flecs aborts once its abort
hook returns; the plugin's hook logs the message and the stack at the failure first, through the
log callback the host set.

## What the parts agree on without a contract

- The invalid entity is `KE_ENTITY_INVALID` (0), and the plugin also treats component id 0 as
  invalid, while `KE_COMPONENT_INVALID` is declared as the all-ones value.
- A destroyed or never-materialized id is refused by the plugin's add as an invalid argument; get
  returns null, and destroy and remove leave it alone.
