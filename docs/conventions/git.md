# How does work reach main?

Work happens on a local branch and reaches `main` only as a merge commit. `main` is never committed
to directly, and a work branch is not pushed.

## The path

1. Work on a local branch. Cleaning its history before the merge (squashing fixups, rewording, dropping
   experiments) is encouraged, so what merges reads as the logical commits.
2. Merge it into `main` with `git merge --no-ff`, never fast-forward. The merge commit's message is one
   line, a Conventional Commit (`feat`, `fix`, `refactor`, `docs`, `test`, `chore`) that summarises the
   branch, with no body and no `Co-Authored-By` footer. The changelog is read from these messages with
   `git log --first-parent`.
3. Run `scripts/ci_local.cs` on that `main`, cold on Linux and with `--windows` (`docs/conventions/ci.md`).
4. If it passes, push `main`. If it fails, reset `main` to `origin/main`, fix on the branch and merge
   again; `main` is not rewritten.

## The one exception to not pushing a branch

When the remote CI fails and the cause cannot be reproduced locally, a work branch is pushed to run it
there, and deleted afterwards. A local run is necessary and not sufficient: Wine tolerates what the real
Windows runtime does not.

## What checks it

The `main-history` job in `.github/workflows/ci.yml` runs on a push to `main` and fails when the push adds
a commit to the first-parent line that is not a merge, a merge whose subject is not a one-line
Conventional Commit, or a merge with a body. It reports after the push and does not prevent it; the local
run and `--no-ff` are what prevent it.
