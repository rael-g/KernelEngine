# 0004. Behavior two plugins share is Zig source passed by the build, not a contract header

Recorded: 2026-10-13. The decision is older than this record.

## Context
Plugins must not export or share symbols other than their factory, and a contract header declares
vtable shapes only. Several plugins need the same error recording, allocator, field writer and test
fakes.

## Decision
The shared behavior is a Zig file under `src/zig/common/` (or `src/zig/render/common/`). The root build
passes its path to each consumer as an option named after the file, and the consumer imports it as a
module. A file that touches C types is a function of the consumer's own translated C namespace.

## Consequences
Each plugin gets its own compiled copy, with types that are its own. The shared files carry no tests;
the plugins that import them test them.
