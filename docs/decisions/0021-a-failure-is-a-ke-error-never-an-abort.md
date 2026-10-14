# 0021. A failure is a ke_error, never an assert or an abort

Recorded: 2026-10-13. The decision is older than this record.

## Context

An assert or an abort ends the process of whoever loaded the plugin, with no type and no message the
host can act on. A managed host sees its process disappear.

## Decision

Every condition that could fail, internal guards included, fills a `ke_error` and returns the
failure sentinel of the call. Nothing in engine code asserts, panics or aborts.

## Consequences

- A host decides what a failure means; the managed layer turns it into an exception of the matching
  type.
- Code that turns an allocation failure into a crash is debt, counted by a gate.
- A library that aborts on its own internal failure is the one place this does not hold, and is
  recorded as debt.
