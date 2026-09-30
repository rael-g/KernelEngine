# Documentation

Each entry is the question that document answers. If your question is not one of these, the answer
is in the code, and `CLAUDE.md`'s closing table says where to start looking.

## Conventions

- [How this project's documentation is written](conventions/docs.md) — the rules every document
  here obeys, and the line between a contract and a moment.

## Architecture

- [How is the engine divided into layers, and where does each kind of file live?](architecture/layers.md)
- [How does a call cross the C ABI, and how does a failure come back?](architecture/abi.md)
- [How does one runtime tick run, and what may run at the same time?](architecture/runtime.md)
- [Which threads exist, what runs on them, and how does work reach them?](architecture/threading.md)

## Not here, on purpose

**Status, plans, logs, tasks and ideas are not versioned.** They live in `docs/kanban/`, which is
excluded from git. A document under `docs/` that starts by telling you where the project currently
stands is a document that will be wrong shortly and cannot be corrected by reading it.

**Architecture and format references are being rewritten from the code**, one at a time, after the
previous set was retired for mixing the two. `git log -- docs/` reaches every retired document;
none of them is a source. Until a replacement exists, the header, the build file or the
implementation is the answer — and it was the real answer the whole time.
