using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework.Legacy;

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
        FrameworkBackends.Default                  = factory;
        FrameworkBackends.ScenePropertiesResolver  = NativeSceneProperties.For;
        InputActions.CreateBackend                 = factory.CreateInputActions;
        return services;
    }
}
