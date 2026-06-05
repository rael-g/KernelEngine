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

    // Walks every wrapped node, looks at its scene_properties bag, and creates
    // a Material from MaterialBaseColor if the node hasn't already been given
    // one programmatically. Runs during scene-load (before the sim loop) so
    // the resource-queue → render-thread round-trip can complete without the
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

        ISceneLoaderBackend? loader = null;
        try
        {
            loader = backends.CreateSceneLoader(world, tree.NativeWrapper, registry, AppContext.BaseDirectory);

            // Phase 5.4 of ECS-pure nodes: register a C# script factory so the
            // loader can materialise wrapper instances for [entity.script]
            // language="csharp" blocks. Mirrors the legacy NodeTypeRegistrar
            // create callback but lives in the script-language API instead.
            loader.RegisterScriptLanguage("csharp", (entity, typeName) =>
            {
                var type = NodeTypeRegistrar.ResolveNodeType(typeName);
                if (type is null) return false;
                var node = (Node)(services is not null
                    ? ActivatorUtilities.CreateInstance(services, type)
                    : Activator.CreateInstance(type)!);
                tree.WrapEntity(node, entity);
                return true;
            });

            loader.Load(path);

            // Phase 5.4 deadlock fix: MeshRenderer.Start can't safely call
            // ResourceManager.CreateMaterialAsync().GetResult() during the sim
            // tick — the render thread is then waiting for a packet that the
            // sim thread is trying to write, so the await never completes
            // (legacy worked because NodeTypeRegistrar.ApplyProperty ran here,
            // during OnReady, while the render thread was draining commands).
            // Pre-resolve every MeshRenderer's MaterialBaseColor here so Start
            // finds Material already set.
            if (resources is not null)
                PreResolveMaterialsFromBag(tree, resources);

            // Phase 5.4 lifetime fix: scene_properties components point into the
            // loader's per-entity arena. The loader has to outlive every entity
            // that carries that component (i.e. its own world), so we transfer
            // ownership to the Tree which disposes it at world shutdown.
            tree._retainedLoaders.Add(loader);
            loader = null;
        }
        finally
        {
            loader?.Dispose(); // only fires if Load threw before we transferred
            if (ownsRegistry) registry.Dispose();
        }
    }
}
