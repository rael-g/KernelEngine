using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Kernel;

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
}
