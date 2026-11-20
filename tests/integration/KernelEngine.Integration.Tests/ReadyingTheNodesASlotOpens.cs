using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Scheduler.Native;

using Microsoft.Extensions.DependencyInjection;

using Xunit;

namespace KernelEngine.Integration.Tests;

/// <summary>A node that records its tag when it becomes ready.</summary>
[NodeType("probe")]
partial class Probe : Node
{
    internal static readonly List<int> Readied = [];

    [Export] public partial int Tag { get; set; }

    void Ready() => Readied.Add(Tag);
}

public class ReadyingTheNodesASlotOpens
{
    sealed unsafe class Headless : IDisposable
    {
        readonly ServiceProvider _services;
        public readonly INodeTypes Types;
        public readonly NodeWorld Nodes;
        public readonly Scheduler.Scheduler Scheduler;
        public readonly Schedule.Schedule PreUpdate;

        public Headless()
        {
            _services = new ServiceCollection().AddDefaultKernelEngine(AppContext.BaseDirectory, "headless.composition").BuildServiceProvider();
            var host = _services.GetRequiredService<KernelEngineHost>();
            host.Start();
            Types = _services.GetRequiredKeyedService<INodeTypes>("node_types");
            Nodes = _services.GetRequiredService<NodeWorld>();
            Scheduler = KernelEngine.Scheduler.Scheduler.Borrow((ke_scheduler*)host.Instance("scheduler", "ke_scheduler"));
            PreUpdate = KernelEngine.Schedule.Schedule.Borrow((ke_schedule*)host.Instance("pre_update", "ke_schedule"));
        }

        public void OpenAndTick(string scene)
        {
            var slot = new SceneSlotComponent { Path = scene };
            Types.Spawn(PreUpdate.Commands(), Nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(Nodes.Component("scene_slot"), slot)]);
            for (var i = 0; i < 10 && Probe.Readied.Count == 0; i++) Scheduler.Tick(1.0f / 60.0f);
            Scheduler.Tick(1.0f / 60.0f);
            Scheduler.Shutdown();
        }

        public void Dispose() => _services.Dispose();
    }

    [Fact]
    public void ANodeOfTheOpenedSceneAndOneOfASceneItInstantiatesAreBothReadied()
    {
        using var engine = new Headless();
        engine.Nodes.Register(new Probe());
        Probe.Readied.Clear();

        engine.OpenAndTick("res://scenes/Opened.scene.toml");

        Assert.Equal([1, 2], Probe.Readied.Order());
    }

    [Fact]
    public void A_scene_places_nodes_under_a_bare_node_that_carries_no_component()
    {
        using var engine = new Headless();
        engine.Types.RegisterType(name: "node");
        engine.Nodes.Register(new Probe());
        Probe.Readied.Clear();

        engine.OpenAndTick("res://scenes/Grouped.scene.toml");

        Assert.Equal([3], Probe.Readied);
    }
}
