# How does one runtime tick run, and what may run at the same time?

The mechanism is `runtimeTick` in `src/zig/runtime/src/runtime.zig:862`. This document describes
what that function and the ones it calls do; where they disagree with it, it is wrong.

## Phases, in the order `tick` runs them

`ke_phase` has seven values (`src/c/runtime/kernel_engine/runtime/runtime.h`). The first `tick`
runs `KE_PHASE_STARTUP` once, before anything else. Every tick then runs, in this order:

1. `KE_PHASE_PRE_UPDATE`
2. `KE_PHASE_FIXED_UPDATE`, zero or more times
3. `KE_PHASE_UPDATE`
4. `KE_PHASE_POST_UPDATE`
5. `KE_PHASE_RENDER`, dispatched and not awaited

`KE_PHASE_SHUTDOWN` runs once from the runtime's destroy, if a tick ever started it, after the
pending render phase is joined and before the modules unload. A failure there cannot be reported,
because destroy returns nothing. `grep -n 'PHASE_STARTUP\|PHASE_SHUTDOWN' src/zig/runtime/src/runtime.zig`
finds where each runs.

A phase that fails stops the tick: each later sim phase is guarded by `failure.type == null`
(`runtime.zig:880`, `909`, `910`), and inside a phase no wave starts after a failed one (`runtime.zig:731`).

## Fixed timestep

Each tick adds `dt` to an accumulator, clamps it to `fixed_dt_max_accum`, then runs
`KE_PHASE_FIXED_UPDATE` once per `fixed_dt` the accumulator holds, passing `fixed_dt` as the body's
`dt` (`runtime.zig:876-883`). Time beyond the clamp is discarded, not carried over. Defaults
`1/60` and `0.25` apply when the params field is `0` (`runtime.zig:982-983`); the runtime's third
tunable, `max_systems_per_phase`, defaults to `256` (`runtime.zig:985-986`).

## Waves — what may run concurrently

A phase's systems are split into **waves**; systems in one wave are dispatched together and the wave
ends at a barrier. Two systems conflict when they name the same component and at least one of them
writes it (`runtime.h:37-41`; `systemsConflict`, `runtime.zig:132-149`). The access a system names
is the union of its queries' terms and its `access_list` (`runtime.zig:101-125`).

Wave assignment is greedy and in registration order (`debugComputeWaves`,
`runtime.zig:151-189`): a system joins the current wave unless it conflicts with a system already in
it, in which case it opens the next wave. A closed wave is never reopened, so a later system can
never overtake an earlier one it does not conflict with.

A system that declares nothing conflicts with nothing and runs beside everything in its phase
(`runtime.h:120-125`). The declared access is scheduling input: `CtxState.access_list` is stored
when a wave is built (`runtime.zig:695`) and read nowhere else.

### Dispatch

Every system body in a wave becomes a scheduler task: `dispatch` for a free body, `dispatch_pinned`
when `pinned_thread` is non-zero (`runWaveBody`, `runtime.zig:603-611`). The tick thread then waits
for every task in the wave (`runtime.zig:613-624`).

A system marked `per_entity` is run as several concurrent slices of its entity set
(`sliceCountFor`, `runtime.zig:736`); each slice learns its share from the `slice` slot of its `ke_system_ctx`
(`ctxSlice`, `runtime.zig:247`). A pinned system is never sliced.

## Structural change — the defer queue

A system body reads component memory only through its `ke_system_ctx`
(`src/c/runtime/kernel_engine/runtime/system_ctx.h`), whose `view` and `slice` slots hand it the
segments of its queries and its share of them (`runtime.zig:200`, `runtime.zig:247`). It cannot add
or remove an entity or component directly: the context carries a `ke_ecs_commands`
(`src/c/ecs/kernel_engine/ecs/commands.h`), and `spawn`, `attach`, `detach`, `despawn` and `defer`
record into a queue owned by that body's own call (`commandsSpawn` and its siblings,
`runtime.zig:274-345`). The queue is applied after the wave's barrier (`deferFlush`,
`runtime.zig:355`, called at `runtime.zig:758`). Nothing one body queued is visible to a sibling in
the same wave.

`ke_ecs_commands` has one meaning wherever it is used: it records, and the queue's owner applies.
A caller that needs a change visible at once uses `ke_ecs`, which mutates immediately; there is no
immediate flavour of the queue. `ke_scene_tree` follows the same split with `create_node` and
`destroy_node` (immediate) beside `create_node_deferred` and `destroy_node_deferred`, which take the
queue.

`spawn` returns the new entity's id at once, so the body can attach to it in the same call; the
entity enters the world at the barrier (`runtime.zig:274`). `attach` refuses a payload whose size
differs from the component's registered size, with a `ke_error`, when it is recorded.

The render phase has no queue: `allow_defer` is false there (`runtime.zig:747`), the body's queue
pointer stays null (`runtime.zig:617`), and every operation on its `ke_ecs_commands` fails with
`not_supported` (`recordTarget`, `runtime.zig:253`).

## Sim and render — how they are decoupled

The render phase does not read live storage. After the sim phases finish, `runtimeExtractRenderState`
copies each render system's query results — entity ids and every term's column — into buffers the
runtime owns (`runtime.zig:766-842`), and the render phase's queries resolve to those copies
(`runtime.zig:679` is guarded by `phase != KE_PHASE_RENDER`).

The render phase is then submitted as one scheduler task and `tick` returns
(`runtime.zig:894-903`). It runs alongside the **next** tick's sim phases. Before that next tick
extracts again, it waits for the pending render task (`runtimeJoinPendingRender`,
`runtime.zig:852`, called at `runtime.zig:888`), so the buffers are never overwritten while a render
body reads them.

Because the render phase outlives the tick that started it, its failure is reported by the next
tick's join, or by `flush_render` (`runtime.h:166-176`; `runtimeFlushRender`, `runtime.zig:915`). A
caller must call `flush_render` before destroying anything the render phase uses.

## How a failure in a body reaches the caller

A body runs on a worker thread, so the error record cannot travel: it lives in that thread's
per-thread storage ([abi.md](abi.md#what-the-error-record-holds)). What crosses is the error
**type** only (`taskPkgRun`, `runtime.zig:583-593`). The tick thread raises a fresh error of that
type, carrying the failing system's name as its message (`E.failWithType`, `runtime.zig:890`).

The remaining bodies of the failing wave still run, since they were already dispatched; no later
wave and no later phase starts (`runtime.h:86-90`).

## Modules

A module is a pair of hooks registered with `register_module` (`runtime.h:68-81`): `on_load`
registers the module's components and systems and runs **before `register_module` returns**
(`runtime.zig:451`); `on_unload` runs when the runtime is destroyed. A call with no params, or with no
`on_load`, is refused (`runtime.zig:423-427`).

What the runtime keeps of a module is its `user_data` and its `on_unload` — not its name
(`RegisteredModule`, `runtime.zig:378-381`). The record is stored **before** `on_load` runs
(`:460-461`). When `on_load` returns false, the record is cleared, `register_module` returns `0`, and
the refused module's `on_unload` never runs (`:465-468`; test `:1316`). Nothing
removes a system, so systems that module registered before it refused stay registered.

`runtimeDestroy` first joins a pending render task, then calls every `on_unload` in **reverse
registration order**, on the calling thread, and only afterwards frees its system storage
(`runtime.zig:928-940`; test `:1294`). Registration order is the order of the `register_module`
calls; the managed layer decides that order ([managed-layer.md](managed-layer.md#load-order)).

## What the runtime keeps from a system registration

`register_system` copies the params struct shallowly (`rs.params = p.*`, `runtime.zig:496`). Two of
its pointers are then replaced by the runtime's own storage, and one is not:

- **queries**: when the system declares at least one, each declaration is copied into the system
  record, and the access list is merged with the queries' terms into the runtime's own array
  ; `access_list` then points into that record's merged array and the query fields are cleared;
- **access list with no queries**: the merge is inside the same branch, so a system that declares
  no query keeps the **caller's** `access_list` pointer, and the wave builder reads it again every
  time its phase runs (`:666-680`, `systemsConflict`, `:137-154`);
- **name**: never copied. Each wave's context takes `rs.params.name` (`:714`), a failing body is
  blamed by that pointer (`:637`), and `failWithType` stores it as the raised error's message without
  copying (`:914`, `src/zig/common/kerror.zig:76-85`).

The contract says what the name is for (`runtime.h:102`) and not how long it must stay valid, so
what a caller must keep alive is read off the code above: the name for as long as the runtime can tick, and
the access list likewise when the system has no query.

## Registering a system while a tick runs

`register_system` called from a body of any phase, render included, does not touch the system table, which other threads are reading.
It builds the system, takes its id, and pushes it on a lock-free stack. The next `tick` applies the
stack, in registration order, before its first phase, after joining a render phase still running
against the table. `unregister_system` from a body is queued the same way and applied after the
registrations of that stack.

## How many segments and queries there are

Neither is capped. A system's per-query storage is allocated from the number of queries it declares.
Each query starts with room for a few segments; when `query_resolve` reports more matches than the
buffer holds, the runtime grows the buffer to that count and resolves again, before the wave is
dispatched, so no body ever holds a buffer that moves. The render extraction scratch grows the same
way. The only failure left is an allocation failure, which fails the tick with `out_of_memory`. A
query's width is not capped either: `ke_runtime_system_params` carries the terms of every query
back to back in `query_terms`, and `query_widths` says how many each takes. A query that the ecs
cannot register fails the tick naming the system.
