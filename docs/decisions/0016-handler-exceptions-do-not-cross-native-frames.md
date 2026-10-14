# 0016. A managed handler's exception is caught at the trampoline and rethrown by the next managed call

Recorded: 2026-10-13. The decision is older than this record.

## Context
A managed delegate is called by a native thread. An exception cannot unwind through native
frames, and the native error record carries a message and no managed type.

## Decision
Every trampoline catches. A handler with an error lane writes the message to it; one that outlives
the registering call also enqueues the exception on the wrapper. A handler without a lane parks
it. The managed call that observes a failure throws the queued exception (wrapped in
`InvalidOperationException`) in place of the native error.

## Consequences
The original exception type comes back only on a call that asks; until then it waits in the
queue. Only the message survives the native error lane. The scheduler's pinned dispatch has no
result to fault and uses a static event, so a failure is lost if nothing subscribes.
