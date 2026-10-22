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
| managed bridge | `LogCallback`, `LogCallbackNative`, generated from `ke_log_callback` | a managed handler | the callback pointer and the context a setter takes |
| managed logger | `Logger`, `ILogger` | a `LogLevel`, a tag and a message | the event to every sink that admits it |
| managed sink | `ILoggerSink` | events whose level reaches its `MinLevel` | whatever the sink does with them |

## What ties the parts together

**Nothing links a logger.** A plugin logs with `std.log` and receives no logger. Each plugin
library is its own destination, since `std_options.logFn` is fixed per binary at compile time; the
host injects where its lines go through the library's setter, once, before the library logs.

**The scope says who logged.** A plugin logs under the scope of its library's name; a third-party
library a plugin routes logs under that library's own name.

**Until a callback is set, lines go to stderr.** A null callback sends them back there.

**The managed side reaches the setters through its wrappers.** The code that creates a library's
objects hands the setter `LogCallbackNative.Pointer` and `LogCallbackNative.Pin(logger.Log)`, with
the `ILogger` from the container, so a native line arrives as `ILogger.Log` with the scope as the
tag.

**The filter is the sink's.** The managed logger has no level of its own; it offers an event to
each sink whose `MinLevel` the event reaches, in the order the sinks were added.

**Composition.** `AddLogger` registers the logger and, when it is first resolved, adds the
`ILoggerSink` services registered by then. `AddConsoleSink` registers the console sink.

## What the parts agree on without a contract

- The section "logging" and the key "console_level" of the project file, read by `AddConsoleSink`
  and holding a `LogLevel` name.
- The console format, `[LEVEL] tag: message`.
- The setter's name, `<library>_set_log_callback`, spelled from the library name by the `log` module.
