#!/bin/sh
# See zig-cc.sh.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$root/build/zig-cache}"
export ZIG_LOCAL_CACHE_DIR
exec zig c++ -idirafter /usr/include -L/usr/lib/x86_64-linux-gnu -L/usr/lib "$@"
