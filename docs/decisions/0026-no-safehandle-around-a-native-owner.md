# 0026. A native owner is a pointer with Dispose, not a SafeHandle

Date: 2026-10-13

## Context

SafeHandle is the .NET convention for a native handle. It gives two things: release from the
finalizer, and protection against a handle being released during a call, which is automatic only
when the handle is a P/Invoke parameter.

## Decision

The generated owner class keeps the native pointer and the destroy function and releases them in
Dispose. It is not a SafeHandle.

## Consequences

- Calls go through function pointers of the vtable, so the protection would have to be written by
  hand around every call.
- A finalizer would call destroy on the collector's thread in arbitrary order, while the engine has
  an order of teardown and resources tied to a thread.
- A finalizer may report a leak in a debug build; it never destroys.
