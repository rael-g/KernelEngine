#!/bin/sh
# No `-target`: native resolution is required to match the host glibc's
# symbol versions. `-idirafter` adds the host's system include/lib paths
# (needed for X11 etc., which Zig does not search by default) after Zig's
# own bundled libc++ headers, so it never outranks them.
exec zig cc -idirafter /usr/include -L/usr/lib/x86_64-linux-gnu -L/usr/lib "$@"
