#!/bin/sh
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$root/build/zig-cache}"
export ZIG_LOCAL_CACHE_DIR
exec zig cc -target x86_64-windows-gnu "$@"
