using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Kernel;

public static class ServiceCollectionExtensions
{
    /// <summary>Registers the kernel factory.</summary>
    public static IServiceCollection AddKernel(this IServiceCollection services)
    {
        services.AddSingleton<IKernelFactory, KernelFactory>();
        return services;
    }
}
