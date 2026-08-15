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

    private KernelEngine.Input.IInputReader? _inputSnapshot;

    public string Name => "SceneNodes";

    public IEnumerable<Type> Dependencies => new[] { typeof(FrameworkModule) };

    /// <summary>Setup callback that only needs the node world.</summary>
    public SceneNodesModule(Action<NodeWorld> setup) => _setup = (nw, _) => setup(nw);

    /// <summary>Setup callback that also wants to resolve DI services.</summary>
    public SceneNodesModule(Action<NodeWorld, IServiceProvider> setup) => _setup = setup;

    public void Configure(IServiceCollection services)
    {
        services.AddSpatialNodeTypes();
        services.AddSingleton<NodeWorld>(sp =>
            new NodeWorld(
                sp.GetRequiredService<World>(),
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>(),
                sp.GetService<KernelEngine.Logger.ILogger>(),
                sp.GetRequiredService<SignalBus>()));
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var nodeWorld = services.GetRequiredService<NodeWorld>();
        var world     = services.GetRequiredService<World>();
        var sceneTree = world.SceneTree;
        var input     = services.GetService<IInput>();
        var scheduler = services.GetRequiredService<IScheduler>();
        var evaluator = services.GetService<IActionEvaluator>();

        var hierarchyCid = nodeWorld.CidOfName("hierarchy");
        var nameCid      = nodeWorld.CidOfName("name");

        runtime.RegisterSystem("Scene.Input", RuntimePhase.PreUpdate, (_, _, _) =>
        {
            input?.Update();
            _inputSnapshot = input?.CaptureSnapshot();
            evaluator?.Evaluate(_inputSnapshot);
        }, accessList: Array.Empty<ComponentAccess>(), pinnedThread: 1);

        var signals = services.GetService<SignalBus>();
        if (signals is not null)
        {
            runtime.RegisterSystem("Scene.Signals.Clear", RuntimePhase.PreUpdate, (_, _, _) =>
                signals.ClearFrame(), accessList: Array.Empty<ComponentAccess>());

            runtime.RegisterSystem("Scene.Signals.Deliver", RuntimePhase.PostUpdate, (_, ctx, _) =>
            {
                unsafe
                {
                    uint count = 0;
                    var list = signals.Deliveries(&count);
                    if (list == null) return;
                    using (nodeWorld.EnterSystem(ctx))
                        for (uint i = 0; i < count; i++)
                            nodeWorld.Deliver(in list[i]);
                }
            }, accessList: Array.Empty<ComponentAccess>());
        }

        nodeWorld.BehaviorTypeAdded += type =>
        {
            var probe = (Node)nodeWorld.BehaviorsOf(type)[0];
            var names = new List<string>();
            probe.CollectBehaviorComponents(names);

            var access = new List<ComponentAccess>
            {
                ComponentAccess.Read(hierarchyCid),
                ComponentAccess.Read(nameCid),
            };
            foreach (var n in names)
            {
                var cid = nodeWorld.CidOfName(n);
                if (cid == hierarchyCid || cid == nameCid) continue;
                if (access.Any(a => a.Cid == cid)) continue;
                access.Add(ComponentAccess.Write(cid));
            }

            runtime.RegisterSystem($"Scene.Behaviors.{type.Name}", RuntimePhase.Update, (_, ctx, dt) =>
            {
                var view      = new View(nodeWorld, dt, _inputSnapshot, ctx);
                var behaviors = nodeWorld.BehaviorsOf(type);
                using (nodeWorld.EnterSystem(ctx))
                {
                    for (int i = 0; i < behaviors.Count; i++)
                        behaviors[i].OnUpdate(in view);
                }
            }, accessList: access.ToArray());
        };

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
