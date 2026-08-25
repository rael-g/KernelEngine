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

    /// <summary>
    /// The half-open range of <paramref name="count"/> items this body call owns. A
    /// system the runtime chose not to slice reports one slice, so the range is the
    /// whole set and the caller needs no second code path.
    /// </summary>
    /// <remarks>
    /// Counted in entities rather than in archetype segments: instances of one node
    /// type share an archetype, so a whole type is usually one segment, and splitting
    /// by segment would hand every entity to a single slice and leave the rest idle.
    /// </remarks>
    private static (int First, int Last) SliceOf(nint ctx, int count)
    {
        KernelEngine.Runtime.SystemContext.Slice(ctx, out var index, out var slices);
        if (slices <= 1) return (0, count);

        var per   = count / (int)slices;
        var first = (int)index * per;
        return (first, index == slices - 1 ? count : first + per);
    }

    public void Configure(IServiceCollection services)
    {
        services.AddSpatialNodeTypes();
        services.AddSingleton<ScriptHost>(sp =>
        {
            unsafe
            {
                var ecs = sp.GetRequiredService<INativeEcs>();
                KernelEngine.Common.Native.ke_error* err = null;
                var handle = Native.NativeMethods.script_host_create(ecs.Native, null, &err);
                if (handle.@ref == null) throw KernelError.FromNative(err, "script_host_create");
                return new ScriptHost(handle);
            }
        });
        services.AddSingleton<NodeWorld>(sp =>
            new NodeWorld(
                sp.GetRequiredService<World>(),
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<ScriptHost>(),
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

        DeclareSignals(nodeWorld, services);

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
            var uses = new List<NodeComponentUse>();
            probe.CollectBehaviorComponents(uses);

            var owned  = new Dictionary<uint, bool>();
            var reached = new Dictionary<uint, bool>();
            foreach (var use in uses)
            {
                var cid = nodeWorld.CidOfName(use.Name);
                if (cid == hierarchyCid || cid == nameCid) continue;
                var into = use.Owned ? owned : reached;
                into[cid] = into.TryGetValue(cid, out var w) ? w || use.Writes : use.Writes;
            }

            var terms = owned
                .Select(e => e.Value ? ComponentAccess.Write(e.Key) : ComponentAccess.Read(e.Key))
                .ToArray();

            var access = new List<ComponentAccess>
            {
                ComponentAccess.Read(hierarchyCid),
                ComponentAccess.Read(nameCid),
            };
            foreach (var (cid, isWrite) in reached)
                if (!owned.ContainsKey(cid))
                    access.Add(isWrite ? ComponentAccess.Write(cid) : ComponentAccess.Read(cid));

            var queries = terms.Length is > 0 and <= QueryDecl.MaxTerms ? new[] { new QueryDecl(terms) } : null;
            if (queries is null)
                foreach (var (cid, isWrite) in owned)
                    access.Add(isWrite ? ComponentAccess.Write(cid) : ComponentAccess.Read(cid));

            runtime.RegisterSystem($"Scene.Behaviors.{type.Name}", RuntimePhase.Update, (_, ctx, dt) =>
            {
                var view = new View(nodeWorld, dt, _inputSnapshot, ctx);
                using (nodeWorld.EnterSystem(ctx))
                {
                    if (queries is null)
                    {
                        var behaviors = nodeWorld.BehaviorsOf(type);
                        var (from, upto) = SliceOf(ctx, behaviors.Count);
                        for (int i = from; i < upto; i++)
                            behaviors[i].OnUpdate(in view);
                        return;
                    }

                    var segments = KernelEngine.Runtime.SystemContext.SegmentCount(ctx);
                    var total = 0;
                    for (int s = 0; s < segments; s++)
                        total += KernelEngine.Runtime.SystemContext.EntitiesOf(ctx, 0, s).Length;

                    var (first, last) = SliceOf(ctx, total);
                    var ran = 0;
                    var seen = 0;
                    for (int s = 0; s < segments && seen < last; s++)
                    {
                        var entities = KernelEngine.Runtime.SystemContext.EntitiesOf(ctx, 0, s);
                        for (int e = 0; e < entities.Length; e++, seen++)
                        {
                            if (seen < first) continue;
                            if (seen >= last) break;
                            if (nodeWorld.NodeOf(entities[e]) is { } node && node.GetType() == type)
                            {
                                node.OnUpdate(in view);
                                ran++;
                            }
                        }
                    }

                    KernelEngine.Runtime.SystemContext.Slice(ctx, out uint _, out uint slices);
                    if (slices == 1)
                        nodeWorld.ReportUnmatchedBehavior(type, ran, nodeWorld.BoundCountOf(type));
                }
            }, queries: queries, accessList: access.ToArray(), perEntity: probe.ReachesOnlyItself);
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

    /// <summary>
    /// Registers every signal any known node type emits or handles, before the first
    /// scene is read. That ordering is the whole point: the loader can only reject a
    /// misspelled signal name if the real names are already there to compare against.
    /// </summary>
    private static void DeclareSignals(NodeWorld nodeWorld, IServiceProvider services)
    {
        var registry = services.GetService<NodeTypeRegistry>();
        if (registry is null) return;

        foreach (var type in registry.RegisteredTypes)
        {
            var probe = (Node)ActivatorUtilities.CreateInstance(services, type);
            probe.CollectSignalTypes(nodeWorld);
        }
    }
}
