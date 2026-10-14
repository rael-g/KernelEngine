# 0006. A failure crosses threads as an error type, and the waiter raises a fresh error

Recorded: 2026-10-13. The decision is older than this record.

## Context
A task body runs on a worker. A `ke_error` lives in that thread's own storage and is recycled
before another thread could read it.
## Decision
A body reports failure by writing a `ke_error_type`, a program-lifetime node, to its failure
out-pointer. `wait` builds a new error from the type on the waiting thread; the runtime does the
same on the tick thread, with the failing system's name as the message.
## Consequences
Only the category of a failure survives the thread crossing; the original message does not. The
rest of a failing wave still runs, and no later wave or phase starts. A task nobody waits on
reports its failure nowhere.
