# 0032. A signal is declared by the node that uses it

Date: 2026-10-14.

## Context

A scene connects a signal by name, so the signal bus must know the name before the connection is
read. The scene module learned every name at load by constructing one unbound instance of every
registered node type and asking it which payload types it handles or emits. Each constructor ran
with the real services, for a node no scene had asked for.

## Decision

A signal is declared when something uses it. The generated `GeneratedBind` of a node declares the
payload types the node handles through `On` or emits through an `Emit` parameter; `Connect<T>` and
emitting declare theirs by resolving the id. The scene loader reads connections only after every
entity of the scene exists and its node is bound, so the nodes at both ends have declared the
signal by then.

## Consequences

- No node is constructed to be asked a question; `CollectSignalTypes`, `ISignalDeclarer` and the
  load-time probe are gone.
- A connection naming a signal that no node bound so far uses fails, where before it passed if any
  registered type used it.
- Declaring is idempotent and costs a lookup per signal for each node bound.
