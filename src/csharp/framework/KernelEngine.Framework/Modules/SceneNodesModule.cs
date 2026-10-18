using KernelEngine.Ecs;
using KernelEngine.Input;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Runtime module "SceneNodes", depending on <see cref="FrameworkModule"/>. It registers the
/// <see cref="ScriptHost"/> and the spatial node types, and registers these systems: "Scene.Input"
/// (pre-update, writing <see cref="ScriptHost.StateCid"/>: releases retired handles, updates and snapshots input and
/// evaluates actions), "Scene.Signals.Clear" (pre-update) and "Scene.Signals.Deliver"
/// (post-update) when a <see cref="SignalBus"/> is registered, and one system
/// "Scene.Behaviors.&lt;type&gt;" in the update phase for each node type with behavior,
/// registered when the first node of that type binds. That system declares the component access
/// of the type's <see cref="Node.CollectBehaviorComponents"/>: the owned components form its
/// query and the reached ones its access list, with hierarchy and name always read, and it is
/// sliced per entity when the type reaches only itself. <c>OnLoad</c> runs the setup callback on the
/// calling thread.
/// </summary>
public sealed class SceneNodesModule : IRuntimeModule
{
    private readonly Action<ScriptHost, IServiceProvider> _setup;

    private KernelEngine.Input.IInputReader? _inputSnapshot;

    /// <summary>The module name, "SceneNodes".</summary>
    public string Name => "SceneNodes";

    /// <summary>The module that creates the world.</summary>
    public IEnumerable<Type> Dependencies => new[] { typeof(FrameworkModule) };

    /// <summary>Setup callback that only needs the node world.</summary>
    public SceneNodesModule(Action<ScriptHost> setup) => _setup = (nw, _) => setup(nw);

    /// <summary>Setup callback that also wants to resolve DI services.</summary>
    public SceneNodesModule(Action<ScriptHost, IServiceProvider> setup) => _setup = setup;

    /// <summary>
    /// The half-open range of <paramref name="count"/> items this body call owns; the whole range
    /// for a system that is not sliced.
    /// </summary>
    private static (int First, int Last) SliceOf(nint ctx, int count)
    {
        var (index, slices) = KernelEngine.Runtime.SystemCtx.Of(ctx).Slice();
        if (slices <= 1) return (0, count);

        var per = count / (int)slices;
        var first = (int)index * per;
        return (first, index == slices - 1 ? count : first + per);
    }

    /// <summary>Registers the spatial node types and the <see cref="ScriptHost"/>.</summary>
    /// <exception cref="InvalidOperationException">
    /// The native script host cannot be created when the service is first requested.
    /// </exception>
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

    /// <summary>
    /// Registers the systems and runs the setup callback on the calling
    /// thread.
    /// </summary>
    /// <exception cref="InvalidOperationException">The setup callback throws.</exception>
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scriptHost = services.GetRequiredService<ScriptHost>();
        var world = services.GetRequiredService<World>();
        var sceneTree = world.SceneTree;
        var input = services.GetService<IInput>();
        var evaluator = services.GetService<IActionEvaluator>();

        var hierarchyCid = scriptHost.CidOfName("hierarchy");
        var nameCid = scriptHost.CidOfName("name");

        runtime.RegisterSystem("Scene.Input", RuntimePhase.PreUpdate, (_, _) =>
        {
            scriptHost.ReleaseRetired();
            input?.Update();
            _inputSnapshot = input?.CaptureSnapshot();
            evaluator?.Evaluate(_inputSnapshot);
        }, accessList: [Touches(scriptHost.StateCid, writes: true)]);

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

            var owned = new Dictionary<uint, bool>();
            var reached = new Dictionary<uint, bool>();
            foreach (var use in uses)
            {
                var cid = scriptHost.CidOfName(use.Name);
                if (cid == hierarchyCid || cid == nameCid) continue;
                var into = use.Owned ? owned : reached;
                into[cid] = into.TryGetValue(cid, out var w) ? w || use.Writes : use.Writes;
            }

            var terms = owned.Select(e => Touches(e.Key, e.Value))
                .Append(Touches(scriptHost.TagOf(type), writes: false))
                .ToArray();

            var access = new List<ComponentAccess>
            {
                Touches(hierarchyCid, writes: false),
                Touches(nameCid, writes: false),
            };
            foreach (var (cid, isWrite) in reached)
                if (!owned.ContainsKey(cid))
                    access.Add(Touches(cid, isWrite));

            var queries = new[] { new QueryDecl { Terms = terms } };

            void Register(string name, RuntimePhase phase, bool fixedStep) =>
                runtime.RegisterSystem(name, phase, (ctx, dt) =>
                {
                    var view = new View(scriptHost, dt, _inputSnapshot, ctx);
                    using (scriptHost.EnterSystem(ctx))
                    {
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
                                if (scriptHost.NodeOf(entities[e]) is { } node)
                                    Run(node, in view, fixedStep);
                            }
                        }
                    }
                }, queries: queries, accessList: access.ToArray(), perEntity: probe.ReachesOnlyItself);

            if (probe.HasBehavior) Register($"Scene.Behaviors.{type.Name}", RuntimePhase.Update, fixedStep: false);
            if (probe.HasFixedBehavior) Register($"Scene.FixedBehaviors.{type.Name}", RuntimePhase.FixedUpdate, fixedStep: true);
        };

        try { _setup(scriptHost, services); }
        catch (Exception ex) { throw new InvalidOperationException("Scene setup failed", ex); }
    }

    private static void Run(Node node, in View view, bool fixedStep)
    {
        if (fixedStep) node.OnFixedUpdate(in view);
        else node.OnUpdate(in view);
    }

    private static ComponentAccess Touches(uint cid, bool writes) =>
        new() { Cid = cid, Access = writes ? RuntimeAccess.Write : RuntimeAccess.Read };
}
