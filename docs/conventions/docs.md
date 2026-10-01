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

**3. No checkboxes and no "delivered" tables.** A list of what shipped is a log. It belongs in the
kanban or in `git log`, both of which are better at it and neither of which pretends to be a
contract.

**4. Every load-bearing claim cites its source as `file:line`.** A statement about how the system
behaves is an invitation to read the code that makes it behave that way. Where a document and the
code disagree, the code wins and the document is the bug — and a citation is what makes that
resolvable in seconds instead of an afternoon. A claim nobody can check is a claim nobody should
believe, including its author six months on.

**5. One document answers one question.** If the title needs "and", there are two documents. The
title should be the question, so the index can be read instead of the corpus.

## What this costs, deliberately

These rules make documentation *harder* to write and much cheaper to trust. Writing a mechanism
down without leaning on "as of this branch" forces the author to find out what is actually true,
which is the work the old documents avoided — and avoided at the reader's expense, compounding.

A document that cannot be written under these rules is usually a document whose subject is not
settled yet. That is useful information: it belongs in the kanban as a question, not in `docs/` as
an answer.

## The same reasoning, applied elsewhere

Source comments are banned in this project for exactly this reason, and the ban had to be widened
once — from comments to `<remarks>` — because rationale and history kept finding a new place to
hide. Doc comments (`///`, `<summary>`) survive because they carry *API contract*: what a caller
must pass, what it gets back, what fails. The moment one starts explaining why the author chose
something, or what used to be there, it is the same defect in a smaller font.
