# 0019. A plugin exposes vtables behind one factory per header

Recorded: 2026-10-13. The decision is older than this record.

## Context

A plugin could export a function per operation. Every exported name is then part of the ABI, a
binding has to resolve each by name, and swapping an implementation means matching a list of
symbols.

## Decision

A contract header declares structs of function pointers and nothing else. A plugin exports one
create function per factory header; everything else is reached through the vtable that function
returns. Only the shared kernel library exports plain functions.

## Consequences

- An implementation is swapped by calling another factory; no caller changes.
- A binding in any language needs the factory symbol and the layout of the vtable, which is what
  lets one generator project every contract.
- A convenience that wants to be a plain exported function has to become a slot or move to a
  contract.
