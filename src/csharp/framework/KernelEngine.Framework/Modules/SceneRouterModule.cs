using KernelEngine.Configuration;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;

namespace KernelEngine.Framework;

/// <summary>
/// Runtime module "Scene.Router". It registers <see cref="ISceneRouter"/>, registers the script
/// factory of the native scene loader (it resolves the type name through
/// <see cref="NodeTypeRegistry"/>, constructs the node with the service provider and binds it to
/// the entity), loads the initial scene on the pinned worker during <c>OnLoad</c>, and registers
/// the system "Scene.Router.Flush" in the pre-update phase on that worker. The initial scene is the
/// constructor override, else the "default_scene" key of the "project" configuration section
/// with its <c>res://</c>, <c>scenes/</c> and scene extension removed, else "Main".
/// </summary>
public sealed class SceneRouterModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    private readonly string? _initialSceneOverride;
    private readonly Type    _sceneModuleDependency;

    /// <summary>The module name, "Scene.Router".</summary>
    public string Name => "Scene.Router";

    /// <summary>The module that registers <see cref="ScriptHost"/>.</summary>
    public IEnumerable<Type> Dependencies => new[] { _sceneModuleDependency };

    /// <param name="initialScene">Overrides the project's default scene, if set.</param>
    /// <param name="sceneModuleDependency">
    /// The module that must load first. Defaults to <see cref="SceneNodesModule"/>.
    /// </param>
    public SceneRouterModule(string? initialScene = null, Type? sceneModuleDependency = null)
    {
        _initialSceneOverride  = initialScene;
        _sceneModuleDependency = sceneModuleDependency ?? typeof(SceneNodesModule);
    }

    /// <summary>Registers the router as itself and as <see cref="ISceneRouter"/>.</summary>
    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<SceneRouter>();
        services.AddSingleton<ISceneRouter>(sp => sp.GetRequiredService<SceneRouter>());
    }

    /// <summary>
    /// Registers the script factory, loads the initial scene and registers the flush system.
    /// </summary>
    /// <exception cref="InvalidOperationException">The initial scene fails to load.</exception>
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<IScheduler>();
        var loader    = services.GetRequiredService<SceneLoader>();
        var scriptHost = services.GetRequiredService<ScriptHost>();
        var types     = services.GetRequiredService<NodeTypeRegistry>();
        var router    = services.GetRequiredService<SceneRouter>();
        var initial   = ResolveInitialScene(services);

        loader.RegisterScriptFactory((entity, typeName) =>
        {
            var type = types.Resolve(typeName);
            var node = (Node)ActivatorUtilities.CreateInstance(services, type);
            scriptHost.BindNativeEntity(node, entity);
        });

        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;
        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try
            {
                router.LoadScene(initial);
                router.Flush();
            }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });
        done.Wait();
        if (err is not null)
            throw new InvalidOperationException("Initial scene load failed", err);

        runtime.RegisterSystem("Scene.Router.Flush", RuntimePhase.PreUpdate, (ctx, _) =>
        {
            using (scriptHost.EnterSystem(ctx))
                router.Flush();
        }, pinnedThread: RenderWorker);
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
        if (s.StartsWith("res://", StringComparison.Ordinal))   s = s.Substring(6);
        if (s.StartsWith("scenes/", StringComparison.Ordinal))  s = s.Substring(7);
        if (s.EndsWith(".scene.toml", StringComparison.Ordinal)) s = s.Substring(0, s.Length - 11);
        else if (s.EndsWith(".scene", StringComparison.Ordinal)) s = s.Substring(0, s.Length - 6);
        return s;
    }
}
