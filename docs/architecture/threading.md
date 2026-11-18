# Threading

This is a map: the systems that own threads, who submits to them and where work lands. The contracts
are `ke_job_system` under `src/c/job/`, `ke_async` under `src/c/async/` and `ke_completion` under
`src/c/completion/`; each system has an enkiTS implementation (`src/zig/job/enki/src/job_system_enki.zig`,
`src/zig/async/enki/src/async_enki.zig`) and an inline one that runs everything on the creating thread.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| job system | `ke_job_system`, made by `ke_job_system_enki_create` | jobs of the frame, with dependencies | their execution on workers, as completions |
| async system | `ke_async`, made by `ke_async_enki_create` | operations that tolerate latency and may block | their execution beside the frame, as completions |
| schedule | `ke_schedule` | systems with their component access | system bodies as jobs, ordered by access |
| scheduler | `ke_scheduler_create` | the job and async systems | the frame loop: it drains both and ticks the schedules |
| io | `ke_io_async_create` | reads and writes of files | one async operation per request |
| ecs | `ke_ecs_flecs_create` | nothing from either system | single-threaded storage |

**Threads are made by the host, and no thread is named.** The host creates the job and async systems
and hands each consumer the one it runs on; no plugin starts a thread or uses a foreign pool. No
contract or plugin defines a "sim" or a "render" thread.

**A completion is waited on only where it may be.** `ke_completion.wait` blocks on the thread that
created the system it came from, and inside a job for a completion of that job system; anywhere else
it answers `KE_RESULT_NOT_SUPPORTED` at once, and the completion is passed as a dependency instead.
`poll` answers from any thread.

**A read during a frame does not wait.** A system body runs on a job worker, where an io request
cannot be waited on. The readers a frame reaches (shaders, scene files, fonts, images, sounds) keep
their request in flight with the `pending_reads` package (`src/zig/io/pending_reads/`) and answer
`KE_RESULT_PENDING` until a later call collects it; a read during assembly, on the host, waits.

**The ecs asks for no threads.** `ke_ecs_flecs_create` initializes flecs with `ecs_init` and never
sets a thread count. Structural changes a body makes are recorded into `ke_ecs_commands` and applied
by the schedule after the bodies that could see them.

**Nothing is pinned.** No contract names a worker for a job or a system; an order between two
systems is a component they both access. State that is not a component is named by a component no
entity carries, such as the tag the render frame answers from `frame_cid`.

**The window is not on a worker.** The host polls the window's events on the thread that created
it, before each tick of the scheduler.

**There is no lock to take.** Plugins use no mutex, condition variable or thread of their own;
ordering between producers and consumers is component access and completions.
