using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Input;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;

namespace KernelEngine.Framework;

/// <summary>
/// Scene infrastructure independent of any other domain: registers the
/// <see cref="ScriptHost"/>, installs the BehaviorSystem that propagates transforms
/// and drives per-node <see cref="Node.OnUpdate"/>, and runs a one-shot scene
/// setup callback on a dedicated worker thread. Framework has no concept of any
/// other domain's components or node types (the same rule <c>ke_world</c> follows
/// natively) — render's [entity.components.X] applies and node-type registrations
/// live in <c>WebgpuRenderModule</c>, physics's in its own module, and so on.
/// </summary>
public sealed class SceneNodesModule : IRuntimeModule
{
    private const uint SetupWorker = 1;

    private readonly Action<ScriptHost, IServiceProvider> _setup;

    private KernelEngine.Input.IInputReader? _inputSnapshot;

    public string Name => "SceneNodes";

    public IEnumerable<Type> Dependencies => new[] { typeof(FrameworkModule) };

    /// <summary>Setup callback that only needs the node world.</summary>
    public SceneNodesModule(Action<ScriptHost> setup) => _setup = (nw, _) => setup(nw);

    /// <summary>Setup callback that also wants to resolve DI services.</summary>
    public SceneNodesModule(Action<ScriptHost, IServiceProvider> setup) => _setup = setup;

    /// <summary>
    /// The half-open range of <paramref name="count"/> items this body call owns. A
    /// system the runtime chose not to slice reports one slice, so the range is the
    /// whole set and the caller needs no second code path.
    /// </summary>
    private static (int First, int Last) SliceOf(nint ctx, int count)
    {
        var (index, slices) = KernelEngine.Runtime.SystemCtx.Of(ctx).Slice();
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
                if (handle.@ref == null) throw NativeErrors.FromNative(err, "script_host_create");
                return new ScriptHost(handle).Compose(
                    sp.GetRequiredService<World>(),
                    sp.GetRequiredService<IEcsRegistry>(),
                    sp.GetRequiredService<SignalBus>());
            }
        });
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scriptHost = services.GetRequiredService<ScriptHost>();
        var world     = services.GetRequiredService<World>();
        var sceneTree = world.SceneTree;
        var input     = services.GetService<IInput>();
        var scheduler = services.GetRequiredService<IScheduler>();
        var evaluator = services.GetService<IActionEvaluator>();

        var hierarchyCid = scriptHost.CidOfName("hierarchy");
        var nameCid      = scriptHost.CidOfName("name");

        runtime.RegisterSystem("Scene.Input", RuntimePhase.PreUpdate, (_, _) =>
        {
            scriptHost.ReleaseRetired();
            input?.Update();
            _inputSnapshot = input?.CaptureSnapshot();
            evaluator?.Evaluate(_inputSnapshot);
        }, accessList: [], pinnedThread: 1);

        DeclareSignals(scriptHost, services);

        var signals = services.GetService<SignalBus>();
        if (signals is not null)
        {
            runtime.RegisterSystem("Scene.Signals.Clear", RuntimePhase.PreUpdate, (_, _) =>
                signals.ClearFrame(), accessList: []);

            runtime.RegisterSystem("Scene.Signals.Deliver", RuntimePhase.PostUpdate, (ctx, _) =>
            {
                var list = signals.Deliveries();
                if (list.IsEmpty) return;
                using (scriptHost.EnterSystem(ctx))
                    for (var i = 0; i < list.Length; i++)
                        scriptHost.Deliver(in list[i]);
            }, accessList: []);
        }

        scriptHost.BehaviorTypeAdded += (type, probe) =>
        {
            var uses = new List<NodeComponentUse>();
            probe.CollectBehaviorComponents(uses);

            var owned  = new Dictionary<uint, bool>();
            var reached = new Dictionary<uint, bool>();
            foreach (var use in uses)
            {
                var cid = scriptHost.CidOfName(use.Name);
                if (cid == hierarchyCid || cid == nameCid) continue;
                var into = use.Owned ? owned : reached;
                into[cid] = into.TryGetValue(cid, out var w) ? w || use.Writes : use.Writes;
            }

            var terms = owned.Select(e => Touches(e.Key, e.Value)).ToArray();

            var access = new List<ComponentAccess>
            {
                Touches(hierarchyCid, writes: false),
                Touches(nameCid, writes: false),
            };
            foreach (var (cid, isWrite) in reached)
                if (!owned.ContainsKey(cid))
                    access.Add(Touches(cid, isWrite));

            var queries = terms.Length > 0 ? new[] { new QueryDecl { Terms = terms } } : [];
            var queried = queries.Length > 0;

            runtime.RegisterSystem($"Scene.Behaviors.{type.Name}", RuntimePhase.Update, (ctx, dt) =>
            {
                var view = new View(scriptHost, dt, _inputSnapshot, ctx);
                using (scriptHost.EnterSystem(ctx))
                {
                    if (!queried)
                    {
                        var behaviors = scriptHost.BehaviorsOf(type);
                        var (from, upto) = SliceOf(ctx, behaviors.Count);
                        for (int i = from; i < upto; i++)
                            behaviors[i].OnUpdate(in view);
                        return;
                    }

                    var segments = KernelEngine.Runtime.SystemCtx.Of(ctx).View(0);
                    var total = 0;
                    for (int s = 0; s < segments.Length; s++)
                        total += segments[s].Entities.Length;

                    var (first, last) = SliceOf(ctx, total);
                    var seen = 0;
                    for (int s = 0; s < segments.Length && seen < last; s++)
                    {
                        var entities = segments[s].Entities;
                        for (int e = 0; e < entities.Length; e++, seen++)
                        {
                            if (seen < first) continue;
                            if (seen >= last) break;
                            if (scriptHost.NodeOf(entities[e]) is { } node && node.GetType() == type)
                                node.OnUpdate(in view);
                        }
                    }
                }
            }, queries: queries, accessList: access.ToArray(), perEntity: probe.ReachesOnlyItself);
        };

        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;
        scheduler.DispatchPinned(SetupWorker, () =>
        {
            try   { _setup(scriptHost, services); }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });
        done.Wait();
        if (err != null) throw new InvalidOperationException("Scene setup failed", err);
    }

    private static ComponentAccess Touches(uint cid, bool writes) =>
        new() { Cid = cid, Access = writes ? RuntimeAccess.Write : RuntimeAccess.Read };

    /// <summary>
    /// Registers every signal any known node type emits or handles, before the first
    /// scene is read. That ordering is the whole point: the loader can only reject a
    /// misspelled signal name if the real names are already there to compare against.
    /// </summary>
    private static void DeclareSignals(ScriptHost scriptHost, IServiceProvider services)
    {
        var registry = services.GetService<NodeTypeRegistry>();
        if (registry is null) return;

        foreach (var type in registry.RegisteredTypes)
        {
            var probe = (Node)ActivatorUtilities.CreateInstance(services, type);
            probe.CollectSignalTypes(scriptHost);
        }
    }
}
