using KernelEngine.Configuration;
using KernelEngine.Logger.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Logger;

public static class LoggerServiceCollectionExtensions
{
    /// <summary>
    /// Registers the <see cref="Logger"/> singleton and exposes it as <see cref="ILogger"/> and
    /// <see cref="INativeLogger"/>. When the logger is first resolved it adds every
    /// <see cref="ILoggerSink"/> registered by then, each at its own minimum level.
    /// </summary>
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
    /// Registers the native console sink. Its minimum level is the <c>console_level</c> key of the
    /// <c>logging</c> section of the Project file, and every level when the key is missing.
    /// Throws when the key is not a <see cref="LogLevel"/> name.
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
    /// Registers the native console sink with this minimum level, without reading the Project file.
    /// </summary>
    public static IServiceCollection AddConsoleSink(this IServiceCollection services, LogLevel minLevel)
    {
        services.AddSingleton<ILoggerSink>(new NativeConsoleLoggerSink(minLevel));
        return services;
    }
}

/// <summary>
/// An <see cref="ILoggerSink"/> that forwards each event to the native console sink.
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
