# 0015. A native handle crosses assemblies through an explicitly implemented INative interface

Recorded: 2026-10-13. The decision is older than this record.

## Context
Managed wrappers in one assembly need the native pointer of a wrapper from another, for example
a service building a native plugin from a borrowed logger or ecs. The alternative of sharing
internals between assemblies grants every friend assembly the whole internal surface.

## Decision
Each generated wrapper implements a public `INative<Domain>` interface explicitly. Another
assembly casts to the interface to read `Native`. `InternalsVisibleTo` is not used.

## Consequences
The pointer is not on the class's own surface, but any holder of the object can still cast, so
the mechanism hides the pointer, not protects it. `NativeErrors.FromNative` and `ToNative` are
public for the same reason.
