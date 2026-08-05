
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

public static class SceneServiceCollectionExtensions
{
    /// <summary>
    /// Registers <typeparamref name="T"/> with the scene <see cref="NodeTypeRegistry"/>
    /// under <paramref name="name"/> (defaults to the type's <see cref="Type.FullName"/>).
    /// </summary>
    public static IServiceCollection AddNodeType<T>(this IServiceCollection services, string? name = null)
        where T : Node
    {
        EnsureRegistry(services);
        services.AddSingleton<INodeTypeRegistrar>(_ => new NodeTypeRegistrar<T>(name));
        return services;
    }

    private static void EnsureRegistry(IServiceCollection services)
    {
        if (services.Any(s => s.ServiceType == typeof(NodeTypeRegistry))) return;
        services.AddSingleton<NodeTypeRegistry>(sp =>
        {
            var registry = new NodeTypeRegistry();
            foreach (var r in sp.GetServices<INodeTypeRegistrar>()) r.RegisterInto(registry);
            return registry;
        });
        services.AddSingleton<SceneLoader>(sp =>
            new SceneLoader(
                sp.GetRequiredService<World>(),
                AppContext.BaseDirectory));

        // No builtin node types registered here — Framework has no concept of
        // any other domain's node types (the same "no universe knowledge" rule
        // that keeps ke_world from hardcoding render's components). Each
        // domain's own composition extension (WebgpuRenderModule.Configure,
        // AddPhysics2DBox2D, AddAudioMiniAudio, ...) calls AddNodeType<T>()
        // for its own types.
    }
}

internal interface INodeTypeRegistrar
{
    void RegisterInto(NodeTypeRegistry registry);
}

internal sealed class NodeTypeRegistrar<T> : INodeTypeRegistrar where T : Node
{
    private readonly string? _name;
    public NodeTypeRegistrar(string? name = null) { _name = name; }
    public void RegisterInto(NodeTypeRegistry registry) => registry.Register<T>(_name);
}
