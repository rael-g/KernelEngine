# 0020. A plugin takes no mutex, condition variable or thread of its own

Recorded: 2026-10-13. The decision is older than this record.

## Context

Plugins that each bring their own locks and threads cannot be reasoned about together: the worker
count is no longer one number, and a lock taken inside one plugin can be held across a call into
another. An earlier resource queue rebuilt a future on a mutex and a condition variable and was
deleted.

## Decision

There is one worker pool, behind `ke_scheduler`. Work that must finish elsewhere is dispatched to it
and waited on through it. A producer and a consumer are ordered by the phases of the runtime, not by
a lock.

## Consequences

- Shared state inside a plugin is written lock-free or confined to one thread; the pipeline cache is
  the worked case.
- Thread primitives appear only in tests, and a gate counts them elsewhere.
- A third-party library that starts threads of its own is asked not to.
