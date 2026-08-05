using KernelEngine.Configuration;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;

namespace KernelEngine.Framework;

/// <summary>
/// Wires <see cref="ISceneRouter"/> into the runtime and kicks off the
/// initial scene load.
/// </summary>
public sealed class SceneRouterModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    private readonly string? _initialSceneOverride;
    private readonly Type    _sceneModuleDependency;

    public string Name => "Scene.Router";

    public IEnumerable<Type> Dependencies => new[] { _sceneModuleDependency };

    /// <param name="initialScene">Overrides the project's default scene, if set.</param>
    /// <param name="sceneModuleDependency">
    /// The module that must load first because it registers <see cref="NodeWorld"/> and
    /// drives the behavior system. Defaults to <see cref="SceneNodesModule"/>.
    /// </param>
    public SceneRouterModule(string? initialScene = null, Type? sceneModuleDependency = null)
    {
        _initialSceneOverride  = initialScene;
        _sceneModuleDependency = sceneModuleDependency ?? typeof(SceneNodesModule);
    }

    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<SceneRouter>();
        services.AddSingleton<ISceneRouter>(sp => sp.GetRequiredService<SceneRouter>());
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<IScheduler>();
        var loader    = services.GetRequiredService<SceneLoader>();
        var nodeWorld = services.GetRequiredService<NodeWorld>();
        var types     = services.GetRequiredService<NodeTypeRegistry>();
        var router    = services.GetRequiredService<SceneRouter>();
        var initial   = ResolveInitialScene(services);

        loader.RegisterScriptFactory((entity, typeName) =>
        {
            try
            {
                var type = types.Resolve(typeName);
                var node = (Node)ActivatorUtilities.CreateInstance(services, type);
                nodeWorld.BindNativeEntity(node, entity);
                return true;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"[SceneRouter] script factory failed for '{typeName}' entity={entity}: {ex.Message}");
                return false;
            }
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

        runtime.RegisterSystem("Scene.Router.Flush", RuntimePhase.PreUpdate, (_, _) => router.Flush(),
            pinnedThread: RenderWorker);
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
        if (s.EndsWith(".scene", StringComparison.Ordinal))     s = s.Substring(0, s.Length - 6);
        return s;
    }
}
