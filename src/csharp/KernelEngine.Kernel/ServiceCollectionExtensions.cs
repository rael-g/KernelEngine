using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Kernel;

public static class ServiceCollectionExtensions
{
    /// <summary>Registers a <see cref="MallocAllocator"/> as the <see cref="Allocator"/> singleton.</summary>
    public static IServiceCollection AddKernel(this IServiceCollection services)
    {
        services.AddSingleton<Allocator, MallocAllocator>();
        return services;
    }

    /// <summary>Registers a <see cref="Logger"/> singleton backed by the kernel allocator.</summary>
    public static IServiceCollection AddLogger(this IServiceCollection services)
    {
        services.AddSingleton(sp => new Logger(sp.GetRequiredService<Allocator>()));
        return services;
    }

    /// <summary>Registers a <see cref="MessagePipe"/> singleton backed by the kernel allocator.</summary>
    public static IServiceCollection AddMessagePipe(this IServiceCollection services)
    {
        services.AddSingleton(sp => new MessagePipe(
            sp.GetRequiredService<Allocator>(),
            sp.GetService<Logger>()));
        return services;
    }

    /// <summary>
    /// Registers the built-in <see cref="ConsoleSink"/> that mirrors the native <c>ke_console_sink</c>.
    /// </summary>
    public static IServiceCollection AddConsoleSink(
        this IServiceCollection services,
        ke_log_level minLevel = ke_log_level.KE_LOG_LEVEL_TRACE) =>
        services.AddSingleton<ILoggerSink>(_ => new ConsoleSink { MinLevel = minLevel });

}
