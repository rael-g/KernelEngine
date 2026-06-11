using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Runs a one-shot scene setup callback on the render worker during OnLoad,
/// after <see cref="SceneRenderModule"/> has registered components + the Tree.
/// The callback receives the <see cref="Tree"/> for spawning nodes; it also
/// has access to the renderer via <c>tree.Renderer</c> for GPU resource
/// creation (texture / material), which must happen on the render worker.
/// </summary>
public sealed class SceneModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    private readonly Action<Tree, IServiceProvider> _setup;

    public string Name => "Scene";

    public IEnumerable<Type> Dependencies => new[] { typeof(SceneRenderModule) };

    /// <summary>Setup callback that only needs the tree.</summary>
    public SceneModule(Action<Tree> setup) => _setup = (t, _) => setup(t);

    /// <summary>Setup callback that also wants to resolve DI services (asset loaders, custom singletons).</summary>
    public SceneModule(Action<Tree, IServiceProvider> setup) => _setup = setup;

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<ITaskScheduler>();
        var tree      = services.GetRequiredService<Tree>();

        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;
        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try   { _setup(tree, services); }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });

        done.Wait();
        if (err != null) throw new InvalidOperationException("Scene setup failed", err);
    }
}
