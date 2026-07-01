using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Input;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;

namespace KernelEngine.Framework;

/// <summary>
/// Scene infrastructure for the v2 (component-driven) render path. Registers the
/// <see cref="NodeWorld"/>, installs the BehaviorSystem that propagates transforms
/// and drives per-node <see cref="Node.OnUpdate"/>, and runs a one-shot scene
/// setup callback on the render worker. Unlike <c>SceneRenderModule</c> it
/// registers no IRenderer contributors — the render module's forward pass reads
/// the ECS components directly.
/// </summary>
/// <remarks>
/// Add <c>FrameworkModule</c> and the render module before this one: the render
/// module's OnLoad must create the render core (so mesh upload works) before the
/// setup callback runs. Topo-sort preserves registration order for independent
/// modules, so register the render module earlier in the list.
/// </remarks>
public sealed class SceneNodesModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    private readonly Action<NodeWorld, IServiceProvider> _setup;

    public string Name => "SceneNodes";

    public IEnumerable<Type> Dependencies => new[] { typeof(FrameworkModule) };

    /// <summary>Setup callback that only needs the node world.</summary>
    public SceneNodesModule(Action<NodeWorld> setup) => _setup = (nw, _) => setup(nw);

    /// <summary>Setup callback that also wants to resolve DI services.</summary>
    public SceneNodesModule(Action<NodeWorld, IServiceProvider> setup) => _setup = setup;

    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<NodeWorld>(sp =>
            new NodeWorld(
                sp.GetRequiredService<World>(),
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>()));
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var nodeWorld = services.GetRequiredService<NodeWorld>();
        var sceneTree = services.GetRequiredService<World>().SceneTree;
        var input     = services.GetService<IInput>();
        var scheduler = services.GetRequiredService<IScheduler>();

        IInputReader? prevSnapshot = null;
        // Exclusive so OnUpdate callbacks can create/destroy nodes safely
        // (entity creation is forbidden inside concurrent_reads/ecs_readonly_begin).
        runtime.RegisterSystem("Scene.Behaviors", RuntimePhase.Update, (_, dt) =>
        {
            input?.Update();
            sceneTree.PropagateTransforms();
            var snapshot  = input?.CaptureSnapshot();
            var view      = new View(nodeWorld, dt, snapshot, prevSnapshot);
            var behaviors = nodeWorld.Behaviors;
            for (int i = 0; i < behaviors.Count; i++)
                behaviors[i].OnUpdate(in view);
            prevSnapshot = snapshot;
        }, pinnedThread: 1, exclusive: true);

        // Scene setup runs on the render worker (GPU upload has thread affinity),
        // after the render module's OnLoad created the core + registered components.
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
