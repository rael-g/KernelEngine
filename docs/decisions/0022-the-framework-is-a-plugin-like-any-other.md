# 0022. The framework is a plugin reached through contracts

Recorded: 2026-10-13. The decision is older than this record.

## Context

The framework carries the vocabulary of a game: scene tree, world, signals, scripts. It would be
easy to let the managed layer reach it directly because both are opinionated about the same things.

## Decision

The framework is a plugin with vtable contracts beside every other domain's and one factory header
per piece. Nothing reaches it except through those.

## Consequences

- A binding for another language reaches the framework the same way it reaches the renderer.
- Another framework can replace it without the kernel changing.
- A shortcut between the managed layer and the framework is a defect, however convenient.
