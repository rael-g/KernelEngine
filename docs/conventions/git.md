# Git

`main` is the trunk: every commit on it has a Conventional Commit subject, and `scripts/ci_local.cs` has
passed on it before it is pushed.

## The path

- A change of one commit goes straight onto `main`.
- Work of several commits that form one unit goes on a local branch and merges into `main` with
  `git merge --no-ff`, never fast-forward. The merge commit's message summarises the branch.
- A branch is one subject. A commit about something unrelated is moved out by rewriting the branch before
  the merge: a merge whose subject line cannot say what it did is a merge of more than one subject.
  Squashing fixups and dropping experiments before the merge is encouraged.
- A message starts with a subject line: `feat`, `fix`, `refactor`, `docs`, `test` or `chore`, a colon and
  the summary. The changelog is read from the subject lines on `main`.
- A message may have a body, a merge commit included. The body says why the change was made, which the
  diff does not show; it does not retell the diff. The reason for a structural decision, one that outlives
  the commit, is a record under `docs/decisions/` (`docs/conventions/docs.md`).
- No `Co-Authored-By` footer.
- Run `scripts/ci_local.cs` on `main`, cold on Linux and with `--windows` (`docs/conventions/ci.md`). If it
  passes, `main` is ready to push. If it fails, undo the commit or the merge, fix, and run it again.

## Pushing a branch

A work branch is not pushed. The exception is a failing remote CI whose cause cannot be reproduced locally:
the branch is pushed to run it there, and deleted as soon as the problem is solved. A local run is necessary
and not sufficient, because Wine tolerates what the real Windows runtime does not.

## What checks it

The `main-history` job in `.github/workflows/ci.yml` runs on a push to `main` and fails when a commit the
push adds to the first-parent line has a subject that is not a Conventional Commit.
It reports after the push and does not prevent it; the local run is what prevents it.
