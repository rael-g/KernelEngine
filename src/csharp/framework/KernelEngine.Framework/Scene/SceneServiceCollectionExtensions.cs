
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>Service registration of node types.</summary>
public static class SceneServiceCollectionExtensions
{
    /// <summary>
    /// Registers <typeparamref name="T"/> as a node type a scene may name, under
    /// <paramref name="name"/> as well as the scene spelling of its full and short names. The
    /// type is declared to the script host before the initial scene loads. The first call also
    /// registers the <see cref="SceneLoader"/>.
    /// </summary>
    public static IServiceCollection AddNodeType<T>(this IServiceCollection services, string? name = null)
        where T : Node
    {
        EnsureRegistry(services);
        services.AddSingleton(new NodeTypeDeclaration(typeof(T), name));
        return services;
    }

    private static void EnsureRegistry(IServiceCollection services)
    {
        if (services.Any(s => s.ServiceType == typeof(SceneLoader))) return;
        services.AddSingleton<SceneLoader>(sp =>
            new SceneLoader(
                sp.GetRequiredService<KernelEngine.Ecs.INativeEcs>(),
                sp.GetRequiredService<SceneTree>(),
                sp.GetService<SignalBus>(),
                sp.GetRequiredService<ComponentRegistry>(),
                sp.GetRequiredService<AssetResolver>(),
                sp.GetRequiredService<KernelEngine.Io.INativeIo>()));

    }
}

/// <summary>A node type a host registered with <see cref="SceneServiceCollectionExtensions.AddNodeType{T}"/>, and the name it gave.</summary>
/// <param name="Type">The node type.</param>
/// <param name="Name">The extra name a scene may write for it, or null.</param>
public sealed record NodeTypeDeclaration(Type Type, string? Name);
