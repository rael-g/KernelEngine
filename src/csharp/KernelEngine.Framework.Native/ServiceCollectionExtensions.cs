using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers the native (C-plugin-backed) implementation of every
    /// <see cref="IFrameworkBackendFactory"/> entry plus the static fallbacks
    /// (<see cref="FrameworkBackends.Default"/>, <see cref="InputActions.CreateBackend"/>)
    /// so sugar entry points without DI access still find a backend.
    /// </summary>
    public static IServiceCollection AddNativeFramework(this IServiceCollection services)
    {
        var factory = new NativeFrameworkBackendFactory();
        services.AddSingleton<IFrameworkBackendFactory>(factory);
        services.AddSingleton<INodeTypeRegistry>(_ => factory.CreateNodeTypeRegistry());
        FrameworkBackends.Default        = factory;
        InputActions.CreateBackend       = factory.CreateInputActions;
        return services;
    }
}
