using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Loads a <c>*.scene.toml</c> file into a live <see cref="Tree"/>. Thin C# shell over the native
/// <c>ke_scene_loader</c> plugin — TOML parsing, nested scene resolution, transform handling,
/// parent-by-name lookup, and the per-property dispatch all live in the C plugin. The C# side
/// only orchestrates the call and wires the typed reflection-based property binder via
/// <see cref="NodeTypeRegistrar"/>.
/// </summary>
public static class SceneLoader
{
    /// <summary>
    /// Synchronous load. Use <see cref="LoadAsync"/> when the scene file references
    /// <c>res://</c> resources or constructs nodes with DI dependencies.
    /// </summary>
    public static void Load(Tree tree, string path) => RunLoad(tree, path, resources: null, services: null);

    /// <summary>
    /// Async entry point. Today identical to <see cref="Load"/> because the native plugin is
    /// synchronous — <paramref name="resources"/> and <paramref name="services"/> reach the
    /// reflection-based property binder via <see cref="NodeTypeRegistrar"/>'s closure. Will become
    /// genuinely async once the asset resolver plugin ships.
    /// </summary>
    public static Task LoadAsync(Tree tree, string path, ResourceManager resources, IServiceProvider? services = null)
    {
        RunLoad(tree, path, resources, services);
        return Task.CompletedTask;
    }

    private static void RunLoad(Tree tree, string path, ResourceManager? resources, IServiceProvider? services)
    {
        var world  = tree.World;
        var backends = FrameworkBackends.Required;
        bool ownsRegistry = false;
        INodeTypeRegistry registry;
        if (tree.NodeTypeRegistry is { } existing)
        {
            registry = existing;
        }
        else
        {
            // Self-contained fallback for callers (tests, scripts) that didn't wire a registry into
            // the Tree. Built-in framework types and user node types both resolve via the
            // reflection-backed NodeTypeRegistrar fallback registered below.
            registry = backends.CreateNodeTypeRegistry();
            ownsRegistry = true;
            registry.SetFallback(
                tryCreate: (typeName, entity, name) =>
                {
                    var type = NodeTypeRegistrar.ResolveNodeType(typeName);
                    if (type is null) return false;
                    var node = (Node)(services is not null
                        ? ActivatorUtilities.CreateInstance(services, type)
                        : Activator.CreateInstance(type)!);
                    node.Initialize(entity, world, name);
                    return true;
                },
                trySetProperty: (typeName, entity, key, value) =>
                {
                    var node = Node.FromEntity(entity);
                    if (node is null) return false;
                    NodeTypeRegistrar.ApplyProperty(node, key, value, resources);
                    return true;
                });
        }

        try
        {
            using var loader = backends.CreateSceneLoader(world, tree.NativeWrapper, registry, AppContext.BaseDirectory);
            loader.Load(path);
        }
        finally
        {
            if (ownsRegistry) registry.Dispose();
        }
    }
}
