# How does a log event reach a sink?

There is one logger, a vtable `ke_logger` created by `ke_logger_create`, and any number of sinks,
`ke_logger_sink` values the logger owns (`src/c/logger/kernel_engine/logger/logger.h:28-70`). The
only implementation is `src/zig/logger/simple/src/logger_simple.zig`.

## The event

A `ke_log_event` is three fields: an `int32_t level`, a `tag` and a `message`, both `const char *`
(`logger.h:17-22`). It carries no timestamp, thread or source location. `tag` and `message` are
valid only for the duration of the call that receives them, so a sink that wants to keep one copies
it. `level` is a `ke_log_level`, `KE_LOG_LEVEL_TRACE` (0) through `KE_LOG_LEVEL_CRITICAL` (5)
(`log_level.h:13-20`); `ke_log_level_to_string` maps any other value to `"UNKNOWN"`
(`logger_simple.zig:103-112`).

## The native path

`ke_logger.log(self, event)` walks the sinks in the order they were added and calls `sink.log` on
each one whose `min_level` is at or below `event.level` (`logger_simple.zig:34-44`). The filter is
per sink; the logger has no level of its own. A sink whose `log` slot is null is skipped
(`logger_simple.zig:41`), and a null logger or event returns without effect (`logger_simple.zig:35`).
`flush` calls every sink's `flush` the same way (`logger_simple.zig:46-53`).

`add_sink` takes the sink by value and stores it. The logger holds at most `MAX_SINKS` of them,
a constant of 8 behind a fixed array; the ninth call fails with `ke_error` "sink capacity exceeded"
(`logger_simple.zig:16-19`, `:61-64`). `ke_logger_handle.destroy` calls each sink's `destroy` and
frees the logger (`logger_simple.zig:23-32`). Nothing in the file synchronises: `log`, `add_sink` and
`destroy` read and write the same sink array without a lock.

`ke_console_sink_create()` returns a ready sink with `min_level` `KE_LOG_LEVEL_TRACE`
(`logger_simple.zig:93-101`). Its `log` writes `[LEVEL] tag: message` to standard error and flushes
after each entry, with an empty string for a null tag or message (`logger_simple.zig:70-82`). It does
not read its own `min_level`; only the logger does.

## Who emits events

A plugin that logs takes a borrowed `ke_logger *` in its params struct and calls the vtable
directly: `lg.log.?(lg, &ev)` (`src/zig/asset/stb_image/src/stb_image_loader.zig:24-28`). The
pointer is optional; a plugin handed none emits nothing (`stb_image_loader.zig:25`, and
`src/zig/asset/stb_image/include/kernel_engine/asset/stb_image/stb_image_loader.h:24`). Other
plugins that emit this way include the render passes, `render_module`, assimp and miniaudio. Each
sets its own `tag` and one level; there is no shared helper.

On the managed side, `AddLogger` registers a `Logger` singleton, and the same instance as `ILogger`
and as `INativeLogger`, whose `Native` property is the `ke_logger *` (`Logger/ServiceCollectionExtensions.cs:10-22`;
`Logger/Generated/Logger.g.cs:12-16`). Services that create native plugins read `INativeLogger` and
put that pointer in the params they pass; `FrameworkModule` does so for the world
(`src/csharp/framework/KernelEngine.Framework/Modules/FrameworkModule.cs:78`). Managed code logs
through `Logger.Log(level, tag, message)`, which encodes both strings as ASCII, builds a
`ke_log_event` and calls the native `log` (`Logger/Logger.Idiom.cs:17-32`).

## Managed sinks

A managed sink implements `ILoggerSink`: `MinLevel`, `Log(level, tag, message)`, `Flush`
(`Logger.Abstractions/ILogger.cs:17-27`). `Logger.AddSink(ILoggerSink, LogLevel minLevel = Trace)`
wraps it in a `NativeSinkAdapter` and hands that to the generated
`AddSink(ILoggerSinkNative, int minLevel)` (`Logger.Idiom.cs:44-58`). The generated method pins the
adapter with a `GCHandle`, stores the handle in the sink's `handle`, fills the three slots with
`UnmanagedCallersOnly` trampolines, and calls native `add_sink` (`Logger.g.cs:69-83`). The native
`log` then reaches C# through `LogTrampoline`, which recovers the adapter and calls it; the adapter
decodes `tag` and `message` with `Marshal.PtrToStringAnsi` and calls `ILoggerSink.Log`
(`Logger.g.cs:93-98`; `Logger.Idiom.cs:50-55`). `DestroyTrampoline` frees the `GCHandle`
(`Logger.g.cs:107-111`).

`AddLogger` attaches every `ILoggerSink` registered **before** the `Logger` is first resolved; the
sinks are read once, when the singleton is constructed (`ServiceCollectionExtensions.cs:12-18`). It
attaches each with the default `minLevel` of `Trace`.

`AddConsoleSink()` registers `NativeConsoleLoggerSink`, an `ILoggerSink` that wraps the native
`ke_console_sink_create()` value, and reads `logging.console_level` from the project file to set
that native value's `min_level` and its `MinLevel` property (`ServiceCollectionExtensions.cs:30-40`,
`:59-65`). That level does not filter anything. `AddLogger` hands every sink to
`Logger.AddSink(sink)`, which wraps it in a `NativeSinkAdapter` and registers a new native sink whose
`min_level` is the `minLevel` argument, `Trace` by default (`ServiceCollectionExtensions.cs:16`,
`Logger.Idiom.cs:44-45`). The native logger filters on that registered value
(`logger_simple.zig:40`), and the adapter forwards to `ILoggerSink.Log`, never reading `MinLevel` or
the wrapped native `min_level`. `ILoggerSink.MinLevel` has no reader anywhere in `src/` or
`examples/` (`grep -rn MinLevel src examples --include='*.cs'` finds the interface member, its one
implementation and the doc comment). So `logging.console_level` and `AddConsoleSink(LogLevel)` are
accepted and have no effect on output; only the `minLevel` argument of `Logger.AddSink` filters.
