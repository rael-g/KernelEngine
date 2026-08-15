using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Asset;

namespace KernelEngine.Framework;

/// <summary>
/// Registers the asset resolver: the thing that turns a path a scene authored into
/// an uploaded GPU handle.
/// </summary>
/// <remarks>
/// The host adds it, and only a host that wants file-backed assets pays for it. It is
/// not folded into any other module on purpose: which loader decodes an image belongs
/// to the asset domain, and a render or framework module that created one for you
/// would be choosing on your behalf and coupling itself to a domain it only consumes.
/// <para>
/// The loaders are read from the container when present, so
/// <c>AddStbImageLoader()</c> before this is what gives it images to decode. Without
/// them the resolver still exists and simply resolves nothing.
/// </para>
/// </remarks>
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
