using KernelEngine.Configuration;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Wires <see cref="ISceneRouter"/> into the runtime and kicks off the
/// initial scene load.
/// </summary>
public sealed class SceneRouterModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    private readonly string? _initialSceneOverride;

    public string Name => "Scene.Router";

    public IEnumerable<Type> Dependencies => new[] { typeof(SceneRenderModule) };

    public SceneRouterModule(string? initialScene = null)
    {
        _initialSceneOverride = initialScene;
    }

    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<SceneRouter>();
        services.AddSingleton<ISceneRouter>(sp => sp.GetRequiredService<SceneRouter>());
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<ITaskScheduler>();
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

        var config  = services.GetService<IProjectConfig>();
        var project = config?.GetSection("project");
        if (project is not null && project.TryGetValue("default_scene", out var raw) && raw is string s
            && !string.IsNullOrWhiteSpace(s))
        {
            return NormalizeSceneName(s);
        }
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
