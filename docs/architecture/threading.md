# Which threads exist, what runs on them, and how does work reach them?

One pool, reached through one contract. Nothing in the contract or in any plugin names a thread by
role.

## The pool

`ke_scheduler` (`src/c/scheduler/kernel_engine/scheduler/scheduler.h:39`) is a struct of six
function pointers over an opaque handle. Its one implementation is enkiTS
(`src/zig/scheduler/enki/src/enki_scheduler.zig`), created by `ke_scheduler_enki_create`
(`enki_scheduler.zig:202`). The factory takes no worker-count parameter; the pool is whatever
`enkiInitTaskScheduler` makes of the machine (`enki_scheduler.zig:216`).

`get_num_workers` reports enki's thread count minus one (`enki_scheduler.zig:182-188`).

Every subsystem that runs work in parallel goes through this one object. The runtime's wave
dispatcher is a client like any other ([runtime.md](runtime.md#dispatch)); flecs is given no
threads and no pipeline — the plugin only calls `ecs_init()` (`src/zig/ecs/flecs/src/ecs_flecs.zig:567`),
never `ecs_set_threads` or `ecs_progress`.

## A task

`dispatch` schedules a function to run on any worker; `dispatch_on_complete` adds a callback that
runs on the same worker right after the body; `dispatch_pinned` runs it on one named worker
(`scheduler.h:48`, `57`, `82`). Each returns a `ke_task *`.

- **`wait` consumes the task.** It blocks, then frees the task's storage before returning
  (`enki_scheduler.zig:150-170`; the free is line 168). A task is waited on exactly once, and a
  task that is never waited on is never freed.
- `is_completed` only reads a flag (`enki_scheduler.zig:176-179`); it does not release anything.
- `ke_task *` is a tagged pointer: the low bit records whether the task is pinned, so `wait` picks
  the matching enkiTS call (`enki_scheduler.zig:12-59`). Callers must not interpret it.

### What a failing body returns

A body reports failure by writing an error **type** to `out_failure` (`scheduler.h:28`). The type is
a program-lifetime node; a `ke_error` lives in the failing thread's own storage and would be
recycled before anyone read it ([abi.md](abi.md#what-the-error-record-holds)). `wait` builds a fresh
error from the type on the waiting thread, with a message naming the slot, not the failure
(`enki_scheduler.zig:169-172`; `scheduler.h:67-69`).

## Pinning

`dispatch_pinned` takes a worker index (`scheduler.h:78`). The index is enki's; the contract
gives it no name and no meaning. The runtime reads `0` in a system's `pinned_thread` as "any
worker" (`runtime.zig:624`), so a system can only be pinned to index 1 or above.

Who pins, today:

- **No native plugin.** Every render plugin sets `pinned_thread = 0`
  (`grep -rn 'pinned_thread' src/zig/render`).
- **Two managed modules**, each with its own private constant holding the same number:
  `RenderWorker = 1` (`src/csharp/framework/KernelEngine.Framework/Modules/SceneRouterModule.cs:14`)
  and `SetupWorker = 1` (`.../Modules/SceneNodesModule.cs:25`).

There is no `ke.sim` or `ke.render` thread. The strings appear in a few doc comments in contract
headers (`grep -rn 'ke\.sim' src/c src/zig`) and nowhere in a function that dispatches.

## Where an ordinary system body runs

On whichever worker takes its task, unless `pinned_thread` is non-zero
([runtime.md](runtime.md#dispatch)). That includes the window's event poll: `Glfw.PollEvents` is
registered as an unpinned `PreUpdate` system
(`src/csharp/window/KernelEngine.Window.Glfw/GlfwWindowModule.cs:49`).

The render phase is one task dispatched with `dispatch`, not `dispatch_pinned`
(`runtime.zig:927`), and each render system inside it is dispatched into the same pool by the same
wave code.

## Synchronization

There is no mutex, condition variable or raw thread for plugins to use. Ordering between
producers and consumers is expressed as phases and waves ([runtime.md](runtime.md)); waiting on a
single piece of work is `wait`.
