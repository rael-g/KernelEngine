using KernelEngine.Configuration;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;
using Tomlyn.Model;

namespace KernelEngine.Framework;

/// <summary>
/// Wires <see cref="ISceneRouter"/> into the runtime and kicks off the
/// initial scene load. Scene name resolution order:
///   1. The explicit constructor argument.
///   2. The Project file's <c>[project] default_scene</c>, with optional
///      <c>res://</c> prefix and <c>.scene</c> suffix stripped.
///   3. <c>"Main"</c>.
/// Both the first load and every subsequent swap run pinned on the render
/// worker, same as the scene-spawn callback in <see cref="SceneModule"/>.
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
        var router    = services.GetRequiredService<SceneRouter>();
        var initial   = ResolveInitialScene(services);

        // Initial load: synchronous dispatch on the render worker, same shape
        // as SceneModule's setup callback so we end up with a usable tree
        // before the first runtime.Tick.
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

        // Per-tick flush so scripts can request swaps mid-frame and have
        // them apply at the start of the next tick.
        runtime.RegisterSystem("Scene.Router.Flush", RuntimePhase.PreUpdate, (_, _) => router.Flush(),
            pinnedThread: RenderWorker);
    }

    private string ResolveInitialScene(IServiceProvider services)
    {
        if (!string.IsNullOrEmpty(_initialSceneOverride)) return _initialSceneOverride;

        var config = services.GetService<IProjectConfig>();
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
        if (s.StartsWith("res://", StringComparison.Ordinal)) s = s.Substring(6);
        if (s.StartsWith("scenes/", StringComparison.Ordinal)) s = s.Substring(7);
        if (s.EndsWith(".scene", StringComparison.Ordinal))   s = s.Substring(0, s.Length - 6);
        return s;
    }
}
