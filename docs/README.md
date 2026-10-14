# Documentation

The documentation is built into a site, https://rael-g.github.io/KernelEngine/ , with
`dotnet run scripts/verify.cs -- docs`. Each section has an index of its pages:

- [Guides](guides/index.md): each guide shows how to do one thing with the engine, quoting an
  example the build compiles.
- [Architecture](architecture/index.md): one map per domain: its parts, what each receives and what
  it hands on.
- [Decisions](decisions/index.md): why a structural choice was made, one record per decision.
- [Conventions](conventions/index.md): the rules the code and the documents are written to.
- [Formats](formats/index.md): the files the engine reads, and what it does with each key.

The reference pages are generated from the doc comments of the sources by `zig build docs`.
