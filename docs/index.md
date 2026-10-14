# KernelEngine

A microkernel game engine: ABI-stable C contracts, Zig plugins behind them, and a managed C#
layer for game code.

- [Guides](guides/minimal-host.md) show how to use the engine, quoting examples the build
  compiles.
- [Architecture](architecture/layers.md) has one map per domain: its parts and what each hands
  to which.
- [Decisions](decisions/0001-each-kind-of-documentation-lives-where-something-keeps-it-true.md)
  records why a structural choice was made, one file per decision.
- [Conventions](conventions/docs.md) are the rules the code and the documents are written to.
- [Formats](formats/project-file.md) describe the files the engine reads.
- [Reference](../build/native/docs/engine/index.md) is generated from the doc comments of the
  sources: one page per file, for the [engine](../build/native/docs/engine/index.md) and for
  [kabic](../build/native/docs/kabic/index.md).
