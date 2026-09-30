#!/bin/sh
# No `-target`: native resolution is required to match the host glibc's
# symbol versions. `-idirafter` adds the host's system include/lib paths
# (needed for X11 etc., which Zig does not search by default) after Zig's
# own bundled libc++ headers, so it never outranks them.
#
# ZIG_LOCAL_CACHE_DIR: CMake invokes this wrapper with the repo root as its
# working directory, and `zig cc` caches into `$PWD/.zig-cache` by default,
# which is how a cache directory appears in the root no matter what the Zig
# build itself was told.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$root/build/zig-cache}"
export ZIG_LOCAL_CACHE_DIR
exec zig cc -idirafter /usr/include -L/usr/lib/x86_64-linux-gnu -L/usr/lib "$@"
