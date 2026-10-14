# How this project's documentation is written

Documentation here lies by default. Not because anyone wrote a falsehood, but because a document
that mixes *what the system is* with *what we were doing last Tuesday* stays half-true forever:
the design half can remain correct while the status half goes a year stale, and the reader has no
way to tell which half they are standing in.

So the line is drawn by subject, not by quality:

> **A versioned document describes a contract or a mechanism. Anything that describes a moment —
> status, branch, log, plan, task, idea, estimate — is not versioned.**

Moments are not worthless; they are just not durable, and putting them under `git` alongside
contracts is what makes contracts untrustworthy. They live in the kanban, which is deliberately
unversioned.

## The five rules

**1. No status line.** No `Status:`, no `Branch:`, no "not started", no "accepted at design level".
If a document needs one of these to be understood, it is a plan and it does not belong here.

**2. No moments in the prose either.** No branch names, no commit hashes, no dates, no session
narrative, no `Supersedes:` chain. A document that has been superseded is deleted — `git` already
keeps every word of it, and a reader who finds it in `docs/` cannot know it was retired.

The record of a decision is the one exception. It describes a moment on purpose: what was known,
what was chosen and what follows from it, with its date. It is never edited afterwards and never
cited as a description of the system as it is. A decision that replaces another is a new record,
and the replaced one gains a single line naming it.

**3. No checkboxes and no "delivered" tables.** A list of what shipped is a log. It belongs in the
kanban or in `git log`, both of which are better at it and neither of which pretends to be a
contract.

**4. Every load-bearing claim names its source: the declaration and its file.** A statement
about how the system behaves is an invitation to read the code that makes it behave that way.
Where a document and the code disagree, the code wins and the document is the bug, and a name
is what makes that resolvable in seconds instead of an afternoon. The source is named by the
declaration, in backticks, and the file it is in, never by a line number: a name that is gone is
found missing, while a line number goes on pointing at something else. A claim nobody can check
is a claim nobody should believe, including its author six months on.

**5. One document answers one question.** If the title needs "and", there are two documents. The
title should be the question, so the index can be read instead of the corpus.

## What this costs, deliberately

These rules make documentation *harder* to write and much cheaper to trust. Writing a mechanism
down without leaning on "as of this branch" forces the author to find out what is actually true,
which is the work the old documents avoided — and avoided at the reader's expense, compounding.

A document that cannot be written under these rules is usually a document whose subject is not
settled yet. That is useful information: it belongs in the kanban as a question, not in `docs/` as
an answer.

## What is written where

Each kind of content is written in the place where something keeps it true.

- **What a declaration or a file is** is written in the sources, as doc comments, and the build
  generates the reference pages from them. No document repeats it.
- **A rule a machine can check** is a gate: a `scripts/check_*.cs` or a `kabic check`, run by
  `scripts/verify.cs`. A document names the gate and does not restate what it checks. A rule of
  judgment stays as prose.
- **How to use something** is an example under `examples/`, which the build compiles. A guide
  under `docs/guides/` quotes passages of an example and holds no code of its own. The passage is
  delimited in the example by a marker, `#region` in C# and a marker comment in Zig and C, which
  is the one comment an example may carry besides its doc comments.
- **Why something was decided** is a record under `docs/decisions/`, one numbered file per
  decision: context, decision, consequences.
- **How the parts of a domain fit together** is a map under `docs/architecture/`: the parts by
  name, what each hands to which, and only what rarely changes. A map does not describe how a
  part works inside, and it names a part in backticks instead of linking to a line.

## The same reasoning, applied elsewhere

Source comments are banned, and the ban covers every place rationale can be written: `//`,
`/* */`, `<remarks>`, `<para>`, `@note`, a `TODO`, a line of context. A doc comment (`///`,
`<summary>`, Doxygen) carries the API contract and nothing else: what a caller must pass, what it
gets back, what fails. Rationale, history and the name of a consumer do not belong in one.

## The doc comments of an implementation

A doc comment on a declaration (`///` in Zig, `<summary>` in C#) says the part that declaration
plays in the mechanism. On a function: when it runs, what is true once it has returned, and each
failure it reports. On a type: what it holds, who owns it, and how its fields relate to each
other, explained together where they relate.

It is required on a function that implements a slot of a contract and on a type that holds
state. Any other function has one only when there is a precondition or an invariant its body does
not show. A mechanism that crosses several functions is told once, on the type or the function
that owns it. A field, an enum value, a test and a helper of a test have none.

A file doc comment (`//!` in Zig, `@file` in C) is a summary: one to three sentences saying what
the file answers for. It does not tell how the file works; the declarations do. C# has no file
doc comment: the `<summary>` of the type the file declares says it.

They are written to these rules:

**1. It explains, it does not caption.** A doc comment that retells the body of its function, or
restates a name or a signature, is a caption: the reader learns nothing the code below does not
show. It says what the code cannot show from where it stands: the moment it runs, the guarantee
it gives, the reason a caller can rely on it.

**2. Every part it names is a declaration that exists.** A type, function or field is written in
backticks under its real name, and the build warns about a name in backticks that nothing
declares. A parameter, a literal or a key of a file format is not a declaration: it is written in
words, or between quotes.

**3. Every statement closes in the code of the same plugin.** It says nothing about who calls the
plugin, and nothing about another plugin beyond the contract it is used through.

**4. It carries no value the code also carries.** A default, a capacity or a count is named by the
field that holds it, never copied as a number. A literal that is what a caller must match, such as
the shape of a file name or a key of a format, is not such a value: it is written out, between
quotes.

**5. It carries no moment.** No history, no rejected alternative, no plan, no `TODO`.

A comment inside a function body stays banned.
