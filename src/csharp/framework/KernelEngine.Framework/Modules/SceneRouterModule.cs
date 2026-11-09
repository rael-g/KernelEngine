using KernelEngine.Configuration;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Runtime module "Scene.Router". It registers <see cref="ISceneRouter"/>, registers the script
/// factory of the native scene loader (the native script host resolves the type name over the
/// node types the host registered, declared before the initial scene loads; it constructs the node with the service provider and binds it to
/// the entity), loads the initial scene in the system "Scene.Router.Initial" of the startup phase, so
/// after every module has loaded, and registers the system "Scene.Router.Flush" in the pre-update phase, exclusive, so a scene change runs alone before the
/// other systems of the phase. The initial scene is the
/// constructor override, else the "default_scene" key of the "project" configuration section
/// with its <c>res://</c>, <c>scenes/</c> and scene extension removed, else "Main".
/// </summary>
public sealed class SceneRouterModule : IRuntimeModule
{
    private readonly string? _initialSceneOverride;

    /// <summary>The module name, "Scene.Router".</summary>
    public string Name => "Scene.Router";

    /// <param name="initialScene">Overrides the project's default scene, if set.</param>
    public SceneRouterModule(string? initialScene = null) => _initialSceneOverride = initialScene;

    /// <summary>Registers the router as itself and as <see cref="ISceneRouter"/>.</summary>
    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<SceneRouter>();
        services.AddSingleton<ISceneRouter>(sp => sp.GetRequiredService<SceneRouter>());
    }

    /// <summary>
    /// Registers the component and scene apply each node type given to <c>AddNodeType</c> declares,
    /// the script factory, the system that loads the initial scene and the flush system.
    /// </summary>
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var loader = services.GetRequiredService<SceneLoader>();
        var scriptHost = services.GetRequiredService<ScriptHost>();
        var declarations = services.GetServices<NodeTypeDeclaration>().ToList();
        var router = services.GetRequiredService<SceneRouter>();
        var initial = ResolveInitialScene(services);

        var registry = services.GetRequiredService<ComponentRegistry>();
        var ecs = services.GetRequiredService<KernelEngine.Ecs.INativeEcs>();
        var registered = new HashSet<Type>();
        foreach (var d in declarations) NodeTypes.RegisterComponents(d.Type, registry, ecs, registered);

        loader.RegisterScriptFactory((entity, typeName) =>
        {
            var type = scriptHost.NodeTypeNamed(typeName);
            var node = (Node)ActivatorUtilities.CreateInstance(services, type);
            scriptHost.BindNativeEntity(node, entity);
        });

        runtime.RegisterSystem("Scene.Router.Initial", RuntimePhase.Startup, (systemCtx, _) =>
        {
            nint ctx; unsafe { ctx = (nint)((KernelEngine.Runtime.INativeSystemCtx)systemCtx).Native; }
            using (scriptHost.EnterSystem(ctx))
            {
                foreach (var d in declarations) scriptHost.DeclareNodeType(d.Type, d.Name);
                router.LoadScene(initial);
                router.Flush(KernelEngine.Runtime.SystemCtx.Of(ctx).Commands);
            }
        }, exclusive: true);

        runtime.RegisterSystem("Scene.Router.Flush", RuntimePhase.PreUpdate, (systemCtx, _) =>
        {
            nint ctx; unsafe { ctx = (nint)((KernelEngine.Runtime.INativeSystemCtx)systemCtx).Native; }
            using (scriptHost.EnterSystem(ctx))
                router.Flush(KernelEngine.Runtime.SystemCtx.Of(ctx).Commands);
        }, exclusive: true);
    }

    private string ResolveInitialScene(IServiceProvider services)
    {
        if (!string.IsNullOrEmpty(_initialSceneOverride)) return _initialSceneOverride;

        var config = services.GetService<IConfiguration>();
        var raw = config?.GetString("project", "default_scene", "") ?? "";
        if (!string.IsNullOrWhiteSpace(raw)) return NormalizeSceneName(raw);
        return "Main";
    }

    private static string NormalizeSceneName(string raw)
    {
        var s = raw;
        if (s.StartsWith("res://", StringComparison.Ordinal)) s = s.Substring(6);
        if (s.StartsWith("scenes/", StringComparison.Ordinal)) s = s.Substring(7);
        if (s.EndsWith(".scene.toml", StringComparison.Ordinal)) s = s.Substring(0, s.Length - 11);
        else if (s.EndsWith(".scene", StringComparison.Ordinal)) s = s.Substring(0, s.Length - 6);
        return s;
    }
}
