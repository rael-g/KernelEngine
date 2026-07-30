using KernelEngine.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Logger;

public static class LoggerServiceCollectionExtensions
{
    /// <summary>Registers a <see cref="Logger"/> singleton backed by the kernel allocator.</summary>
    public static IServiceCollection AddLogger(this IServiceCollection services)
    {
        services.AddSingleton(sp => new Logger());
        services.AddSingleton<ILogger>(sp => sp.GetRequiredService<Logger>());
        services.AddSingleton<INativeLogger>(sp => sp.GetRequiredService<Logger>());
        return services;
    }

    /// <summary>
    /// Registers the built-in <see cref="ConsoleSink"/> that mirrors the native <c>ke_console_sink</c>.
    /// Reads <c>[logging] console_level</c> from the Project file when present; otherwise passes
    /// through every level.
    /// </summary>
    public static IServiceCollection AddConsoleSink(this IServiceCollection services)
    {
        services.TryAddConfigurationSingleton();
        services.AddSingleton<ILoggerSink>(sp =>
        {
            var cfg = sp.GetRequiredService<IConfiguration>();
            var level = cfg.GetString("logging", "console_level", nameof(LogLevel.Trace));
            return new ConsoleSink { MinLevel = Enum.Parse<LogLevel>(level, ignoreCase: true) };
        });
        return services;
    }

    /// <summary>
    /// Backward-compatible overload that passes the level inline, bypassing the Project file.
    /// Lets examples that have not migrated to Project keep working.
    /// </summary>
    public static IServiceCollection AddConsoleSink(this IServiceCollection services, LogLevel minLevel)
    {
        services.AddSingleton<ILoggerSink>(new ConsoleSink { MinLevel = minLevel });
        return services;
    }
}
