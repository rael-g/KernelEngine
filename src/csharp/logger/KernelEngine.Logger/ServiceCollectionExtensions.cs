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
    /// Registers the console sink, at every level until the runtime loads its modules; then its
    /// minimum level becomes the <c>console_level</c> key of the <c>logging</c> section of the
    /// Project file, and stays every level when the key is missing. Loading throws when the key is
    /// not a <see cref="LogLevel"/> name.
    /// </summary>
    public static IServiceCollection AddConsoleSink(this IServiceCollection services)
    {
        services.TryAddConfigurationSingleton();
        var sink = new ConsoleLoggerSink(LogLevel.Trace);
        services.AddSingleton<ILoggerSink>(sink);
        services.AddSingleton<IRuntimeModule>(new ConsoleLevelModule(sink));
        return services;
    }

    /// <summary>
    /// Registers the console sink with this minimum level, without reading the Project file.
    /// </summary>
    public static IServiceCollection AddConsoleSink(this IServiceCollection services, LogLevel minLevel)
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

/// <summary>
/// Sets the console sink's minimum level from the <c>logging</c> section of the Project file once
/// the container is built, so the logger is created without the configuration.
/// </summary>
internal sealed class ConsoleLevelModule(ConsoleLoggerSink sink) : IRuntimeModule
{
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var cfg = services.GetRequiredService<IConfiguration>();
        var level = cfg.GetString("logging", "console_level", nameof(LogLevel.Trace));
        sink.MinLevel = Enum.Parse<LogLevel>(level, ignoreCase: true);
    }
}
