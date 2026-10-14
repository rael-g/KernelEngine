# 0008. The runtime orders render passes; there is no render graph object

Recorded: 2026-10-13. The decision is older than this record.

## Context
A frame is produced by several passes that depend on each other's outputs. The engine already has a
runtime that places systems into waves from their component access lists. A separate graph object
would duplicate that scheduling and need its own resource model.

## Decision
A render resource is a component id. A pass declares or imports a resource by name through the
service, receives its id and puts it in the access list of its system, which runs in the render
phase. The runtime separates readers from writers as it does for any system.

## Consequences
- A pass is an ordinary runtime system; adding one is registering a system.
- Ordering by access list keeps a reader and a writer apart but does not put the writer first, so
  the order on the GPU needs its own mechanism (record 0009).
- Resources with no data (ordering tags) are component ids too.
