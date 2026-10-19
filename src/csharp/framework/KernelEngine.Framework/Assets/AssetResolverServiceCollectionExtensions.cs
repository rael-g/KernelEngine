using KernelEngine.Asset;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Service registration of the asset resolver.
/// </summary>
public static class AssetResolverServiceCollectionExtensions
{
    /// <summary>Registers <see cref="NativeAssetResolver"/> as a singleton.</summary>
    /// <param name="services">The container to register into.</param>
    /// <param name="projectRoot">
    /// Root for <c>res://</c> resolution. Defaults to the application's base directory.
    /// </param>
    public static IServiceCollection AddAssetResolver(this IServiceCollection services,
                                                      string? projectRoot = null)
    {
        services.AddSingleton(sp => new NativeAssetResolver(
            sp.GetService<INativeImageLoader>(),
            sp.GetService<KernelEngine.Text.INativeFontLoader>(),
            projectRoot ?? AppContext.BaseDirectory));
        return services;
    }
}
