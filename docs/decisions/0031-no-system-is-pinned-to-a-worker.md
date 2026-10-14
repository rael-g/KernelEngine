# 0031. No system is pinned to a worker

Date: 2026-10-14.

## Context

`ke_scheduler` can run a task on a chosen worker, and the runtime passes a system's
`pinned_thread` to it. The managed scene modules used it: the input system and the scene flush
were pinned to worker 1, and their start-up work was dispatched there and waited on. No thread
affinity required it; the window is polled by the host outside the pool. Both systems change the
script host and declared no access to it, so the pin was what kept them out of one wave: a lock
the runtime could not see.

## Decision

Nothing in the engine pins a system or a task. Work runs on whichever worker takes it, and every
ordering between systems is stated as component access, so the runtime can find all the
parallelism there is. State that is not a component is named by a component no entity carries,
the way the render passes name their resources, and declared as read or written.

## Consequences

- The script host has `StateCid`; the scene systems that change the host declare it written.
- Start-up work that ran on a pinned worker runs on the thread that loads the modules.
- The scheduler keeps the capacity, for a library that demands a thread, which nothing does today.
