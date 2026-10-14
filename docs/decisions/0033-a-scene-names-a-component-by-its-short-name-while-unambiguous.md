# 0033. A scene names a component by its short name while it is unambiguous

Date: 2026-10-14.

## Context

A game node's component was registered under the node's class name in snake case, namespace
dropped, so two classes `Paddle` in different namespaces shared one component. The node's `type`
in a scene already followed another rule: the short name when one type answers to it, the
qualified name otherwise.

## Decision

A game node's component is registered under the node type's qualified name, the same normalized
name the type registry uses, and its short name is registered with the world as an alias. The
scene loader resolves a block's name through the world: a registered name, else an alias that a
single component answers to. An alias two components answer to, or one that is also a registered
component's own name, fails naming the candidates, and the scene writes the qualified name
(`[entity."pong.paddle"]`).

## Consequences

- The world contract gains `register_component_alias` and `resolve_component`.
- Component and type names follow one rule, computed by `NodeTypeRegistry.Normalize`, which the
  generated code calls instead of carrying a copy of it.
- Existing scenes keep their short block names.
