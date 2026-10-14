# 0001. Each kind of documentation lives where something keeps it true

Date: 2026-10-11

## Context

The reference documentation is generated: docir reads the doc comments of the sources and the
build writes a page per file. What it cannot give is the conceptual part, how the parts of a
domain fit together and why.

That part was written by hand under `docs/architecture/`, nineteen pages answering one question
each. Nothing checked them against the code, so each was true on the day it was written and
unknown afterwards.

Two ways of generating the conceptual part were tried and dropped. A file doc comment written as
a synthesis of the whole file retold how the file works, which changes with every change to a
body, and nothing but its length was checked. A domain document assembled from parts kept in the
contract headers read well when one author wrote every part with the outline in mind; it was
dropped before parts written apart from each other were tried.

## Decision

Conceptual documentation is not generated. It is split by kind, and each kind is written where
something keeps it true:

- what a declaration or a file is: doc comments in the sources, generated into reference pages;
- a rule a machine can check: a gate that fails the build;
- how to use something: an example the build compiles, quoted by a guide;
- why something was decided: a record like this one, never edited;
- how the parts of a domain fit together: a short map that names parts and holds only what
  rarely changes.

The file doc comment becomes a summary of one to three sentences. A doc comment on a private
function is written only for a precondition or an invariant its body does not show.

A commit message may have a body, which says why the change was made.

## Consequences

- The pages of `docs/architecture/` are taken apart, each passage going to one of the five
  places, and a page is deleted once nothing of it is left.
- The rules of `CLAUDE.md` that a machine can check gain a gate each, and their text shrinks to
  one line.
- A map can still go stale. It is kept short and limited to what rarely changes so that this
  costs little, and it is revised by hand.
- The names a map cites are not checked by anything yet.
- Guides are rendered by DocFX, whose code include checks that the quoted file exists and
  nothing else.
