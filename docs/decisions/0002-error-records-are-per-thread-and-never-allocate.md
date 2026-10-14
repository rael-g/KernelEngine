# 0002. An error record lives in per-thread storage and its message is copied, never allocated

Recorded: 2026-10-13. The decision is older than this record.

## Context
A failing path must work when the allocator is the reason it failed, and the ABI returns only a
sentinel plus an error output.

## Decision
`ke_error_set` fills one of two per-thread records, each with its own fixed text buffer, and points the
caller's output at it. The message is copied and cut; the file name and the cause are kept by pointer.
Two records are used alternately, so wrapping an error keeps the inner one valid while the outer is built.

## Consequences
A `ke_error` pointer is valid until the next two failures on the same thread; a caller that needs more
copies. A message longer than the buffer is cut.
