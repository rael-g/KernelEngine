using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Runs a one-shot scene setup callback on the render worker during OnLoad,
/// after <see cref="SceneRenderModule"/> has registered components + the NodeWorld.
/// </summary>
public sealed class SceneModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    private readonly Action<NodeWorld, IServiceProvider> _setup;

    public string Name => "Scene";

    public IEnumerable<Type> Dependencies => new[] { typeof(SceneRenderModule) };

    /// <summary>Setup callback that only needs the node world.</summary>
    public SceneModule(Action<NodeWorld> setup) => _setup = (nw, _) => setup(nw);

    /// <summary>Setup callback that also wants to resolve DI services.</summary>
    public SceneModule(Action<NodeWorld, IServiceProvider> setup) => _setup = setup;

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<ITaskScheduler>();
        var nodeWorld = services.GetRequiredService<NodeWorld>();

        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;
        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try   { _setup(nodeWorld, services); }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });

        done.Wait();
        if (err != null) throw new InvalidOperationException("Scene setup failed", err);
    }
}
