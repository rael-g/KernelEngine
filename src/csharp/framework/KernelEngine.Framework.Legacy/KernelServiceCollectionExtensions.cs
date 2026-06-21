using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework.Legacy;

public static class ServiceCollectionExtensions
{
    /// <summary>Registers the kernel factory.</summary>
    public static IServiceCollection AddKernel(this IServiceCollection services)
    {
        services.AddSingleton<IKernelFactory, KernelFactory>();
        return services;
    }
}
