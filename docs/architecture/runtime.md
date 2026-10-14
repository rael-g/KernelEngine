# Runtime

This is a map: the parts the tick touches, what each receives and what it hands on. How a part
works inside is on the generated page of its file. Contracts are under `src/c/runtime/`,
`src/c/scheduler/` and `src/c/ecs/`; the runtime is `src/zig/runtime/src/runtime.zig`.

## The parts

| part | contract | plugin | receives | hands on |
|---|---|---|---|---|
| runtime | `ke_runtime` | runtime | `ke_ecs`, `ke_scheduler`, `ke_runtime_params` | the tick, and the registration of modules and systems |
| ecs | `ke_ecs` | flecs | queries, structural changes | entity ids, segments of columns |
| scheduler | `ke_scheduler` | enki | task functions | their completion, and the type of their failure |
| module | none; `ke_runtime_module_params` | the host or a plugin | the runtime, in `on_load` | components and systems it registers |
| system | `ke_runtime_system_params` | a module | `ke_system_ctx`, a delta time | structural changes, recorded in `ke_ecs_commands` |

The runtime borrows the ecs and the scheduler from the host and never frees them. In the managed
layer `LoadModules` registers every `IRuntimeModule` of the service provider, in dependency order.

## A tick

**The phases run in the order of `ke_phase`.** The first tick runs `KE_PHASE_STARTUP` once. Every
tick then runs `KE_PHASE_PRE_UPDATE`, `KE_PHASE_FIXED_UPDATE` zero or more times,
`KE_PHASE_UPDATE`, `KE_PHASE_POST_UPDATE`, and dispatches `KE_PHASE_RENDER` without waiting for
it. `KE_PHASE_SHUTDOWN` runs once from destroy, if a tick ever ran. A phase that fails stops the
tick.

**A phase is cut into waves.** Systems are taken in registration order. Two systems conflict when
they name the same component and at least one writes it; a system joins the current wave unless
it conflicts with one already in it, and then opens the next. The access of a system is its
queries' terms plus its access list, so a system that declares nothing conflicts with nothing.

**A wave is a set of scheduler tasks.** Each system body becomes one `ke_scheduler` task, or
several slices when the system is `per_entity`; a non-zero `pinned_thread` goes through
`dispatch_pinned`. The tick thread waits for all of them before the next wave.

**Structure changes at the barrier.** A body reaches component memory only through its
`ke_system_ctx` and changes structure only by recording into `ke_ecs_commands`. The recorded
changes are applied after the wave, so no body sees storage move under it.

## Sim and render

**The render phase reads copies.** After the sim phases, `runtimeExtractRenderState` copies what
each render system's queries matched into buffers the runtime owns. The render phase is one
scheduler task that runs beside the next tick's sim phases; the next tick joins it before it
extracts again. Its failure is reported by that join or by `flush_render`.

**A failure crosses threads as a type.** The error record of a body lives in its worker's own
storage, so only the `ke_error_type` goes back; the tick thread raises a fresh error of that type
carrying the failing system's name.

## Registering

**Registration during a tick waits.** `register_system` and `unregister_system` called while a
tick or the render phase is in flight are queued, and the next tick applies them before its first
phase. A module's `on_load` runs before `register_module` returns; destroy calls every
`on_unload` in reverse registration order.

## What the parts agree on without a contract

- The worker index `0` in `pinned_thread` means any worker; the scheduler itself accepts any
  index, and the managed layer pins to index 1.
- The count of phases the runtime sizes its scratch for equals the number of `ke_phase` values.
- A component is identified across modules by the name it was registered under in `ke_ecs`.
