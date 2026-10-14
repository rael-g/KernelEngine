# How does a log event reach a sink?

This is a map: the parts of the logger domain and what each hands on. How a part works inside is
on the generated page of its file. The contract is under `src/c/logger/`, the plugin under
`src/zig/logger/`, the managed side under `src/csharp/logger/`.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| event | `ke_log_event` | a level, a tag and a message from the emitter | itself, to the logger |
| sink | `ke_logger_sink` | events whose level reaches its `min_level` | nothing; it writes them somewhere |
| logger | `ke_logger`, made by `ke_logger_create` | events, and sinks by value through `add_sink` | each event to every sink that admits it |
| console sink | `ke_console_sink_create` | events | one line on standard error |
| managed logger | `Logger`, `ILogger` | strings and a `LogLevel` | `ke_log_event` to the native logger |
| managed sink | `ILoggerSink` | events decoded to strings | whatever the sink does with them |

The native logger and the console sink are both in the plugin `logger_simple`.

## What ties the parts together

**The filter is the sink's.** The logger has no level of its own; it offers an event to each
sink whose `min_level` the event reaches, in the order the sinks were added.

**The logger owns what it is given.** `add_sink` takes the sink by value, and destroying the
logger destroys its sinks.

**A plugin that logs is handed a logger.** A plugin takes a borrowed `ke_logger` in its params
and may be given none, in which case it emits nothing.

**The managed logger is a view of the native one.** `Logger` implements `ILogger` and
`INativeLogger`, so a service that creates a native plugin passes the same `ke_logger` the game
logs through. A managed sink reaches the native logger through an adapter registered with the
`minLevel` given to `AddSink`.

**Composition.** `AddLogger` registers the logger and, when it is first resolved, adds the
`ILoggerSink` services registered by then. `AddConsoleSink` registers the console sink.

## What the parts agree on without a contract

- The section "logging" and the key "console_level" of the project file, read by `AddConsoleSink`
  and holding a `LogLevel` name.
- The console format, `[LEVEL] tag: message`, and the label "UNKNOWN" for a level no label names.
- The library name "ke_logger_simple", which the managed project asks the build to copy.
