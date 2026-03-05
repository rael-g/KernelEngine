using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine;

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
}
