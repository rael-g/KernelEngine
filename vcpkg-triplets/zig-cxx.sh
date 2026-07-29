#!/bin/sh
# See zig-cc.sh.
exec zig c++ -idirafter /usr/include -L/usr/lib/x86_64-linux-gnu -L/usr/lib "$@"
