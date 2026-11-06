using KernelEngine.Configuration;
using KernelEngine.Runtime;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Logger;

public static class LoggerServiceCollectionExtensions
{
    /// <summary>
    /// Registers the <see cref="Logger"/> singleton and exposes it as <see cref="ILogger"/>. When
    /// the logger is first resolved it adds every <see cref="ILoggerSink"/> registered by then,
    /// each at its own minimum level, and receives the log of the configuration libraries, which
    /// are created before it.
    /// </summary>
    public static IServiceCollection AddLogger(this IServiceCollection services)
    {
        services.AddSingleton(sp =>
        {
            var logger = new Logger();
            foreach (var sink in sp.GetServices<ILoggerSink>())
                logger.AddSink(sink);
            unsafe
            {
                var callback = LogCallbackNative.Pointer;
                var ctx = LogCallbackNative.Pin(logger.Log);
                KernelEngine.Configuration.Native.NativeMethods.configuration_set_log_callback(callback, ctx);
                KernelEngine.Configuration.Native.NativeMethods.configuration_toml_set_log_callback(callback, ctx);
            }
            return logger;
        });
        services.AddSingleton<ILogger>(sp => sp.GetRequiredService<Logger>());
        return services;
    }

    /// <summary>
    /// Registers the console sink, writing every line, native or managed, at or above
    /// <paramref name="minLevel"/>.
    /// </summary>
    public static IServiceCollection AddConsoleSink(this IServiceCollection services, LogLevel minLevel = LogLevel.Trace)
    {
        services.AddSingleton<ILoggerSink>(new ConsoleLoggerSink(minLevel));
        return services;
    }
}

/// <summary>
/// An <see cref="ILoggerSink"/> that writes each event to standard error as
/// <c>[LEVEL] tag: message</c>.
/// </summary>
internal sealed class ConsoleLoggerSink(LogLevel minLevel) : ILoggerSink
{
    public LogLevel MinLevel { get; set; } = minLevel;

    public void Log(LogLevel level, string tag, string message) =>
        Console.Error.WriteLine($"[{level.ToString().ToUpperInvariant()}] {tag}: {message}");

    public void Flush() => Console.Error.Flush();
}
