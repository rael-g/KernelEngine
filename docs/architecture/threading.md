# Threading

This is a map: the pool, who submits to it and where work lands. Contract is `ke_scheduler` under
`src/c/scheduler/`; the only implementation is `src/zig/scheduler/enki/src/enki_scheduler.zig`.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| pool | `ke_scheduler`, made by `ke_scheduler_enki_create` | task functions | their execution on workers |
| runtime | `ke_runtime_create` | the pool | system bodies and the render phase, as tasks |
| ecs | `ke_ecs_flecs_create` | nothing from the pool | single-threaded storage |
| managed layer | `IScheduler` | actions | tasks on the pool |

**There is one pool and no named thread.** Workers are addressed by index. No contract or plugin
in the engine's native side defines a "sim" or a "render" thread.

**The runtime is a client of the pool.** A system body runs as a task on whichever worker takes
it, or on the worker named by its `pinned_thread` when that is non-zero. The render phase is one
task submitted with `dispatch`, and its systems are submitted into the same pool by the same
wave code. See runtime.md.

**The ecs asks for no threads.** `ke_ecs_flecs_create` initializes flecs with `ecs_init` and
never sets a thread count. Structural calls of `ke_ecs` are single-threaded; `entity_reserve` is
the one that may be called from any wave thread.

**A task is waited on once.** `dispatch`, `dispatch_on_complete` and `dispatch_pinned` return a
`ke_task`; `wait` blocks, releases it and raises the body's failure on the waiting thread.

**Nothing is pinned.** Index `0` is "any" for the runtime, and every system registers with it;
an order between two systems is a component they both access. State that is not a component is
named by a component no entity carries, such as the tag `KE_RENDER_FRAME_COLOR`.

**The window is not on the pool.** The host calls `IWindow.PollEvents` on the thread that created
the window, before each `Tick`.

**There is no lock to take.** Plugins use no mutex, condition variable or thread of their own;
ordering between producers and consumers is phases and waves, and waiting on one piece of work is
`wait`.

## What the parts agree on without a contract

- Worker indexes are the enkiTS ones, and `get_num_workers` excludes the calling thread.
