using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Input;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;

namespace KernelEngine.Framework;

/// <summary>
/// Scene infrastructure independent of any other domain: registers the
/// <see cref="NodeWorld"/>, installs the BehaviorSystem that propagates transforms
/// and drives per-node <see cref="Node.OnUpdate"/>, and runs a one-shot scene
/// setup callback on a dedicated worker thread. Framework has no concept of any
/// other domain's components or node types (the same rule <c>ke_world</c> follows
/// natively) — render's [entity.components.X] applies and node-type registrations
/// live in <c>WebgpuRenderModule</c>, physics's in its own module, and so on.
/// </summary>
/// <remarks>
/// Add <c>FrameworkModule</c> and every domain module (render, physics, audio, ...)
/// before this one, so their OnLoad has already registered its own component
/// applies and node types by the time the scene setup callback runs.
/// </remarks>
public sealed class SceneNodesModule : IRuntimeModule
{
    private const uint SetupWorker = 1;

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
        var world     = services.GetRequiredService<World>();
        var sceneTree = world.SceneTree;
        var input     = services.GetService<IInput>();
        var scheduler = services.GetRequiredService<IScheduler>();
        var evaluator = services.GetService<IActionEvaluator>();

        // The ctx-aware overload hands each tick its system context. Node create/
        // destroy issued from a behavior routes through it and defers the structural
        // change to the wave barrier — so this runs as an ordinary parallel-wave
        // system with no exclusive bypass.
        // Behaviors author local transforms; the scene tree's own system turns those
        // into world matrices later in the frame. A node's OnUpdate can reach past
        // this list, and the scheduler cannot see that from here — a behavior
        // touching another domain's components is ordered only by this system
        // being alone in its phase.
        var sceneAccess = new[]
        {
            ComponentAccess.Write(nodeWorld.CidOfName("transform")),
            ComponentAccess.Read(nodeWorld.CidOfName("hierarchy")),
            ComponentAccess.Read(nodeWorld.CidOfName("name")),
        };

        runtime.RegisterSystem("Scene.Behaviors", RuntimePhase.Update, (_, ctx, dt) =>
        {
            input?.Update();
            var snapshot  = input?.CaptureSnapshot();
            evaluator?.Evaluate(snapshot);
            var view      = new View(nodeWorld, dt, snapshot, ctx);
            var behaviors = nodeWorld.Behaviors;
            using (nodeWorld.EnterSystem(ctx))
            {
                for (int i = 0; i < behaviors.Count; i++)
                    behaviors[i].OnUpdate(in view);
            }
        }, accessList: sceneAccess, pinnedThread: 1);

        // Scene setup runs pinned to a worker thread (GPU upload has thread
        // affinity when a render module is present), after every domain
        // module's OnLoad has registered its own components/applies/node types.
        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;
        scheduler.DispatchPinned(SetupWorker, () =>
        {
            try   { _setup(nodeWorld, services); }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });
        done.Wait();
        if (err != null) throw new InvalidOperationException("Scene setup failed", err);
    }
}
