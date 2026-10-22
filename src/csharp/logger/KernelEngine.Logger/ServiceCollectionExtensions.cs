using KernelEngine.Configuration;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Logger;

public static class LoggerServiceCollectionExtensions
{
    /// <summary>
    /// Registers the <see cref="Logger"/> singleton and exposes it as <see cref="ILogger"/>. When
    /// the logger is first resolved it adds every
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
        return services;
    }

    /// <summary>
    /// Registers the console sink. Its minimum level is the <c>console_level</c> key of the
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
            return new ConsoleLoggerSink(Enum.Parse<LogLevel>(level, ignoreCase: true));
        });
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
    public LogLevel MinLevel => minLevel;

    public void Log(LogLevel level, string tag, string message) =>
        Console.Error.WriteLine($"[{level.ToString().ToUpperInvariant()}] {tag}: {message}");

    public void Flush() => Console.Error.Flush();
}
