using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Asset;

namespace KernelEngine.Framework;

/// <summary>
/// Registers the asset resolver: the thing that turns a path a scene authored into
/// an uploaded GPU handle.
/// </summary>
public static class AssetResolverServiceCollectionExtensions
{
    /// <summary>Registers <see cref="NativeAssetResolver"/> as a singleton.</summary>
    /// <param name="services">The container to register into.</param>
    /// <param name="projectRoot">
    /// Root for <c>res://</c> resolution. Defaults to the application's base directory,
    /// which is where a build drops the content it copied.
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
