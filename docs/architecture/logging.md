# Logging

This is a map: the parts of the logging mechanism and what each hands on. How a part works inside
is on the generated page of its file. The contract is under `src/c/logger/`, the shared Zig module
is `src/zig/logger/log.zig`, the managed side is under `src/csharp/logger/`.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| level | `ke_log_level` | nothing | how severe a line is |
| callback | `ke_log_callback` | a context, a level, a scope and a message | whatever the host does with the line |
| library destination | `@import("log").Destination` in each plugin root's `std_options` | every `std.log` line of the library | the line to the callback the host set, or to stderr |
| library setter | `<library>_set_log_callback`, declared in each plugin's `<library>_log.h` | a callback and its context | them to the library's destination |
| managed setter | `NativeMethods.<library>_set_log_callback`, the setter's generated P/Invoke | a callback pointer and its context | them to the library's setter |

## What ties the parts together

**Nothing links a logger.** A plugin logs with `std.log` and receives no logger. Each plugin
library is its own destination, since `std_options.logFn` is fixed per binary at compile time; the
host injects where its lines go through the library's setter, once, before the library logs.

**The scope says who logged.** A plugin logs under the scope of its library's name; a third-party
library a plugin routes logs under that library's own name.

**Until a callback is set, lines go to stderr.** A null callback sends them back there.

**A managed host sets it like any host.** It calls the library's setter through the generated
P/Invoke, with a function pointer and a context of its own.

**The filter and the output are the host's.** The host composes them with the logging builder, as any
.NET application does; a line below the level it set is dropped, native or managed.

## What the parts agree on without a contract

- The setter's name, `<library>_set_log_callback`, spelled from the library name by the `log` module.
