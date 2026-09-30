using KernelEngine.Configuration;
using KernelEngine.Logger.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Logger;

public static class LoggerServiceCollectionExtensions
{
    /// <summary>Registers a <see cref="Logger"/> singleton backed by the kernel allocator.</summary>
    public static IServiceCollection AddLogger(this IServiceCollection services)
    {
        services.AddSingleton(sp =>
        {
            var logger = new Logger();
            foreach (var sink in sp.GetServices<ILoggerSink>())
                logger.AddSink(sink);
            return logger;
        });
        services.AddSingleton<ILogger>(sp => sp.GetRequiredService<Logger>());
        services.AddSingleton<INativeLogger>(sp => sp.GetRequiredService<Logger>());
        return services;
    }

    /// <summary>
    /// Registers the built-in console sink (native <c>ke_console_sink_create</c> — same
    /// <c>[LEVEL] tag: message</c> format and level names as <c>ke_log_level_to_string</c>,
    /// not re-derived here). Reads <c>[logging] console_level</c> from the Project file
    /// when present; otherwise passes through every level.
    /// </summary>
    public static IServiceCollection AddConsoleSink(this IServiceCollection services)
    {
        services.TryAddConfigurationSingleton();
        services.AddSingleton<ILoggerSink>(sp =>
        {
            var cfg = sp.GetRequiredService<IConfiguration>();
            var level = cfg.GetString("logging", "console_level", nameof(LogLevel.Trace));
            return new NativeConsoleLoggerSink(Enum.Parse<LogLevel>(level, ignoreCase: true));
        });
        return services;
    }

    /// <summary>
    /// Backward-compatible overload that passes the level inline, bypassing the Project file.
    /// Lets examples that have not migrated to Project keep working.
    /// </summary>
    public static IServiceCollection AddConsoleSink(this IServiceCollection services, LogLevel minLevel)
    {
        services.AddSingleton<ILoggerSink>(new NativeConsoleLoggerSink(minLevel));
        return services;
    }
}

/// <summary>
/// An <see cref="ILoggerSink"/> that delegates formatting to the native console sink
/// (<c>ke_console_sink_create</c>) instead of re-implementing the `[LEVEL] tag: message`
/// format and level-name mapping in C# — the previous hand-written version drifted
/// (`"CRIT"` vs. the native `ke_log_level_to_string`'s `"CRITICAL"`).
/// </summary>
internal sealed unsafe class NativeConsoleLoggerSink : ILoggerSink
{
    private ke_logger_sink _native = KernelEngine.Logger.LoggerSink.ConsoleSinkCreate();

    public NativeConsoleLoggerSink(LogLevel minLevel) => _native.min_level = (int)minLevel;

    public LogLevel MinLevel => (LogLevel)_native.min_level;

    public void Log(LogLevel level, string tag, string message)
    {
        var tagBytes = System.Text.Encoding.ASCII.GetBytes(tag + '\0');
        var msgBytes = System.Text.Encoding.ASCII.GetBytes(message + '\0');
        fixed (byte* tagPtr = tagBytes, msgPtr = msgBytes)
        fixed (ke_logger_sink* self = &_native)
        {
            var evt = new ke_log_event { level = (int)level, tag = (sbyte*)tagPtr, message = (sbyte*)msgPtr };
            self->log(self, &evt);
        }
    }

    public void Flush()
    {
        fixed (ke_logger_sink* self = &_native) self->flush(self);
    }
}
