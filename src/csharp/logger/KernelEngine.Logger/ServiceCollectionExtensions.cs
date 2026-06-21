using KernelEngine.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace KernelEngine.Logger;

/// <summary>POCO bound to <c>[logging]</c> in the Project file. Default level matches the prior
/// parameterless behavior (all levels through).</summary>
public sealed class ConsoleSinkOptions
{
    public LogLevel ConsoleLevel { get; set; } = LogLevel.Trace;
}

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
    /// Reads <c>[logging]</c> from the Project file when present; otherwise uses
    /// <see cref="ConsoleSinkOptions"/> defaults.
    /// </summary>
    public static IServiceCollection AddConsoleSink(this IServiceCollection services)
    {
        services.AddProjectConfigSection<ConsoleSinkOptions>("logging");
        services.AddSingleton<ILoggerSink>(sp =>
        {
            var opts = sp.GetRequiredService<IOptions<ConsoleSinkOptions>>().Value;
            return new ConsoleSink { MinLevel = opts.ConsoleLevel };
        });
        return services;
    }

    /// <summary>
    /// Backward-compatible overload that passes the level inline. Equivalent to <c>AddConsoleSink()</c>
    /// + <c>Configure&lt;ConsoleSinkOptions&gt;</c>; examples that have not migrated to Project keep working.
    /// </summary>
    public static IServiceCollection AddConsoleSink(this IServiceCollection services, LogLevel minLevel)
    {
        services.AddConsoleSink();
        services.Configure<ConsoleSinkOptions>(o => o.ConsoleLevel = minLevel);
        return services;
    }
}
