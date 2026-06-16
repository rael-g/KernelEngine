using KernelEngine.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace KernelEngine.Kernel;

/// <summary>POCO bound to <c>[logging]</c> in the Project file. Default level matches the prior
/// parameterless behavior (all levels through).</summary>
public sealed class ConsoleSinkOptions
{
    public LogLevel ConsoleLevel { get; set; } = LogLevel.Trace;
}

public static class ServiceCollectionExtensions
{
    /// <summary>Registers a <see cref="MallocAllocator"/> as the <see cref="Allocator"/> singleton.</summary>
    public static IServiceCollection AddKernel(this IServiceCollection services)
    {
        // Install the crash handler first — it must beat any native code that
        // might assert / abort to a useful diagnostic instead of silent death.
        // Idempotent, so calling AddKernel from multiple hosts is fine.
        CrashHandler.Register();

        services.AddSingleton<Allocator, MallocAllocator>();
        services.AddSingleton<IAllocator>(sp => sp.GetRequiredService<Allocator>());
        services.AddSingleton<IKernelFactory, KernelFactory>();
        return services;
    }

    /// <summary>Registers a <see cref="Logger"/> singleton backed by the kernel allocator.</summary>
    public static IServiceCollection AddLogger(this IServiceCollection services)
    {
        services.AddSingleton(sp => new Logger());
        services.AddSingleton<ILogger>(sp => sp.GetRequiredService<Logger>());
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

    /// <summary>Registers an <see cref="Input"/> singleton.</summary>
    public static IServiceCollection AddInput(this IServiceCollection services)
    {
        services.AddSingleton(sp => new Input(sp.GetService<Logger>()));
        services.AddSingleton<IInput>(sp => sp.GetRequiredService<Input>());
        return services;
    }
}
