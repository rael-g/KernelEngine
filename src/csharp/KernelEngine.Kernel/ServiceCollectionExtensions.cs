using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Kernel;

public static class ServiceCollectionExtensions
{
    /// <summary>Registers a <see cref="MallocAllocator"/> as the <see cref="Allocator"/> singleton.</summary>
    public static IServiceCollection AddKernel(this IServiceCollection services)
    {
        services.AddSingleton<Allocator, MallocAllocator>();
        services.AddSingleton<IAllocator>(sp => sp.GetRequiredService<Allocator>());
        services.AddSingleton<IKernelFactory, KernelFactory>();
        return services;
    }

    /// <summary>Registers a <see cref="Logger"/> singleton backed by the kernel allocator.</summary>
    public static IServiceCollection AddLogger(this IServiceCollection services)
    {
        services.AddSingleton(sp => new Logger(sp.GetRequiredService<Allocator>()));
        services.AddSingleton<ILogger>(sp => sp.GetRequiredService<Logger>());
        return services;
    }

    /// <summary>
    /// Registers the built-in <see cref="ConsoleSink"/> that mirrors the native <c>ke_console_sink</c>.
    /// </summary>
    public static IServiceCollection AddConsoleSink(
        this IServiceCollection services,
        LogLevel minLevel = LogLevel.Trace) =>
        services.AddSingleton<ILoggerSink>(_ => new ConsoleSink { MinLevel = minLevel });

    /// <summary>Registers an <see cref="Input"/> singleton.</summary>
    public static IServiceCollection AddInput(this IServiceCollection services)
    {
        services.AddSingleton(sp => new Input(
            sp.GetRequiredService<Allocator>(),
            sp.GetService<Logger>()));
        services.AddSingleton<IInput>(sp => sp.GetRequiredService<Input>());
        return services;
    }
}
