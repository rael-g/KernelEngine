# 0025. Each language is written to its own convention

Date: 2026-10-13

## Context

The tree is C, Zig and C#. Conventions had grown per file: several styles of constant, of doc
comment and of naming lived side by side, and some written rules said the opposite of what the code
did.

## Decision

Where a language has an established convention, the code follows it: the Zig style guide, the .NET
design guidelines, standard C. A departure is allowed only where the C ABI forces one, and is
recorded.

## Consequences

- C headers use an include guard, not pragma once.
- Zig constants are snake_case; formatting is what the formatter of each language produces.
- A choice no language convention covers, such as the name of a state struct, is a project rule and
  is decided separately.
