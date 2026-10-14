# 0028. The Zig cache and package directories stay at the repository root

Date: 2026-10-13

## Context

Everything the build produces was meant to live under one directory. The Zig cache was pointed
there, and it kept reappearing at the root: the temporary directory of a Zig test is created under
the working directory whatever the cache option says, and the package directory has no option at
all.

## Decision

`.zig-cache` and `zig-pkg` are official at the root and ignored by git. The global cache, which does
take an option, stays under the build directory.

## Consequences

- The build commands lose two options.
- One rule, everything under the build directory, gains two named exceptions.
- What still points the cache at the build directory is changed to agree.
