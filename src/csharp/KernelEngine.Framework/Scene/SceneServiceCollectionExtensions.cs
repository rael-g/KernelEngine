using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

public static class SceneServiceCollectionExtensions
{
    /// <summary>
    /// Registers <typeparamref name="T"/> with the scene <see cref="NodeTypeRegistry"/>
    /// under <paramref name="name"/> (defaults to the type's <see cref="Type.FullName"/>).
    /// The singleton registry is created lazily on first registration.
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
        services.AddSingleton<SceneLoader>();

        // Built-in framework types — game code shouldn't have to register
        // these to use them from a .scene file.
        services.AddSingleton<INodeTypeRegistrar>(_ => new NodeTypeRegistrar<Camera>());
        services.AddSingleton<INodeTypeRegistrar>(_ => new NodeTypeRegistrar<DirectionalLight>());
        services.AddSingleton<INodeTypeRegistrar>(_ => new NodeTypeRegistrar<AmbientLight>());
        services.AddSingleton<INodeTypeRegistrar>(_ => new NodeTypeRegistrar<PointLight>());
        services.AddSingleton<INodeTypeRegistrar>(_ => new NodeTypeRegistrar<SpotLight>());
        services.AddSingleton<INodeTypeRegistrar>(_ => new NodeTypeRegistrar<Skybox>());
        services.AddSingleton<INodeTypeRegistrar>(_ => new NodeTypeRegistrar<MeshRenderer>());
        services.AddSingleton<INodeTypeRegistrar>(_ => new NodeTypeRegistrar<Label>());
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
