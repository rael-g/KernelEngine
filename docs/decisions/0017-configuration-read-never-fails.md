# 0017. A configuration read returns the caller's fallback and never fails

Recorded: 2026-10-13. The decision is older than this record.

## Context
Settings come from a file that may be missing or incomplete, and engine code must start
without one.

## Decision
Every getter takes a fallback and returns it for a missing key, a null argument or a value of
another type. An integer entry read as a double is the one conversion. A missing file is not an
error to the loader or `LoadToml`.

## Consequences
A mistyped key is silent: the fallback applies. Only writes and the load report errors.
