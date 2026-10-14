# 0024. The correct shape is chosen over the one that is easy today

Recorded: 2026-10-13. The decision is older than this record.

## Context

A design picked because it ships this week leaves a workaround behind, and workarounds get copied.
The native side was rewritten once, from CMake and C++ to Zig, and the vtable ABI was expensive to
hold to; both are why one generator could later project every contract without a second redesign.

## Decision

When an idea is judged, the question is whether it is the right shape, not how much existing code
would change. A design shown to be wrong is refactored all the way, a rewrite included.

## Consequences

- A local workaround to unblock a narrow problem is still allowed; it is named as one.
- Existing code is not a reason to keep a design.
- Frequency in the code is not endorsement: a shape is a precedent only if it was decided.
