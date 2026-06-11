using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Loads a <c>*.scene.toml</c> file into a live <see cref="Tree"/>. Thin C# shell over the native
/// <c>ke_scene_loader</c> plugin. TOML parsing, nested-scene resolution, transform handling,
/// parent-by-name lookup, and the per-property bag-attachment all live in the C plugin. The C#
/// side only orchestrates the call and registers a language factory that wraps each
/// <c>[entity.script] language = "csharp"</c> entry as the matching <see cref="Node"/> subclass.
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
    /// script factory + the post-load Material resolver via closures. Will become genuinely
    /// async once the asset resolver plugin ships.
    /// </summary>
    public static Task LoadAsync(Tree tree, string path, ResourceManager resources, IServiceProvider? services = null)
    {
        RunLoad(tree, path, resources, services);
        return Task.CompletedTask;
    }

    // Walks every wrapped node, looks at its scene_properties bag, and creates a
    // Material from MaterialBaseColor if the node hasn't already been given one
    // programmatically. Runs during scene-load (before the sim loop) so the
    // resource-queue → render-thread round-trip can complete without the
    // sim/render deadlock that would hit if Start did this work itself.
    private static void PreResolveMaterialsFromBag(Tree tree, ResourceManager resources)
    {
        var resolver = FrameworkBackends.ScenePropertiesResolver;
        foreach (var node in Node.SnapshotRegistry())
        {
            if (node is not MeshRenderer mr || mr.Material is not null) continue;
            if (mr.World is null) continue;
            var props = resolver(mr.World, mr.Entity);
            if (props.IsEmpty) continue;
            if (!props.TryGetVector4("MaterialBaseColor", out var color)) continue;
            mr.Material = resources.CreateMaterialAsync(color).GetAwaiter().GetResult();
        }
    }

    private static void RunLoad(Tree tree, string path, ResourceManager? resources, IServiceProvider? services)
    {
        var world    = tree.World;
        var backends = FrameworkBackends.Required;

        ISceneLoaderBackend? loader = null;
        try
        {
            loader = backends.CreateSceneLoader(world, tree.NativeWrapper, AppContext.BaseDirectory);

            // The script factory resolves the C# type for every
            // [entity.script] language="csharp" block, constructs it via DI when
            // a service provider is available (so Pong.Paddle's
            // IInputActionReader gets injected), then binds the entity through
            // Tree.WrapEntity. The loader publishes the scene_properties
            // component itself — no per-property callback to wire here.
            loader.RegisterScriptLanguage("csharp", (entity, typeName) =>
            {
                var type = NodeTypeResolver.Resolve(typeName);
                if (type is null) return false;
                var node = (Node)(services is not null
                    ? ActivatorUtilities.CreateInstance(services, type)
                    : Activator.CreateInstance(type)!);
                tree.WrapEntity(node, entity);
                return true;
            });

            loader.Load(path);

            // MeshRenderer.Start cannot safely call ResourceManager.CreateMaterialAsync
            // during the sim tick — the render thread would then be waiting on a
            // packet that the sim thread is trying to write while blocked on the
            // material await. We resolve every MeshRenderer's MaterialBaseColor
            // here, still inside OnReady, while the render thread is draining
            // resource commands.
            if (resources is not null)
                PreResolveMaterialsFromBag(tree, resources);

            // scene_properties components point into the loader's per-entity arena.
            // The loader must outlive every entity that holds the component, so
            // ownership transfers to the Tree which disposes the loader at world
            // shutdown.
            tree._retainedLoaders.Add(loader);
            loader = null;
        }
        finally
        {
            loader?.Dispose(); // only fires if Load threw before we transferred
        }
    }
}
