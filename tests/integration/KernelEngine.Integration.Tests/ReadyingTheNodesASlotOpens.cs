using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Io.Pool;
using KernelEngine.Scheduler;
using KernelEngine.TaskPool.Enki;

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
    static NodeTypesConfig NodeSets(DefaultScheduler scheduler)
    {
        uint Phase(string name, PhaseCadence cadence) => scheduler.RegisterSet(name, scheduler.RegisterPhase(name, cadence), []);
        return new NodeTypesConfig { PreUpdate = Phase("pre_update", PhaseCadence.EveryTick), FixedUpdate = Phase("fixed_update", PhaseCadence.Fixed), Update = Phase("update", PhaseCadence.EveryTick), PostUpdate = Phase("post_update", PhaseCadence.EveryTick) };
    }

    [Fact]
    public void ANodeOfTheOpenedSceneAndOneOfASceneItInstantiatesAreBothReadied()
    {
        using var pool = new EnkiTaskPool(null, new TaskPool.TaskPoolConfig { WorkerCount = uint.MaxValue });
        using var files = new StdFileSystem(null, new FileSystem.FileSystemConfig { Root = "." });
        using var io = new PoolIo(null, pool, files);
        using var config = new DefaultConfiguration(null);
        using var input = new Input.DefaultInput();
        using var ecs = new FlecsEcsRegistry(null, new Ecs.EcsConfig { ReservedIdCapacity = 1048576 });
        using var scheduler = new DefaultScheduler(null, ecs, pool, new SchedulerConfig { FixedDt = 1.0f / 60.0f, FixedDtMaxAccum = 0.25f });
        var sets = NodeSets(scheduler);
        using var assets = new DefaultAssetResolver(null, null, null, AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar), io);
        using var tree = new DefaultSceneTree(null, ecs, null, new());
        using var actions = new DefaultInputActions(null, null, input, config, new Framework.InputActionsConfig { Section = "input" });
        using var types = new DefaultNodeTypes(null, scheduler, ecs, tree, actions, sets);
        using var scenes = new DefaultSceneFiles(null, ecs, types, assets, io);
        var nodes = new NodeWorld(types);
        nodes.Register(new Probe());
        Probe.Readied.Clear();

        var slot = new SceneSlotComponent { Path = "res://scenes/Opened.scene.toml" };
        types.Spawn(scheduler.Commands(), nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(nodes.Component("scene_slot"), slot)]);
        for (var i = 0; i < 3; i++) scheduler.Tick(1.0f / 60.0f);
        scheduler.Shutdown();

        Assert.Equal([1, 2], Probe.Readied.Order());
    }

    [Fact]
    public void A_scene_places_nodes_under_a_bare_node_that_carries_no_component()
    {
        using var pool = new EnkiTaskPool(null, new TaskPool.TaskPoolConfig { WorkerCount = uint.MaxValue });
        using var files = new StdFileSystem(null, new FileSystem.FileSystemConfig { Root = "." });
        using var io = new PoolIo(null, pool, files);
        using var config = new DefaultConfiguration(null);
        using var input = new Input.DefaultInput();
        using var ecs = new FlecsEcsRegistry(null, new Ecs.EcsConfig { ReservedIdCapacity = 1048576 });
        using var scheduler = new DefaultScheduler(null, ecs, pool, new SchedulerConfig { FixedDt = 1.0f / 60.0f, FixedDtMaxAccum = 0.25f });
        var sets = NodeSets(scheduler);
        using var assets = new DefaultAssetResolver(null, null, null, AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar), io);
        using var tree = new DefaultSceneTree(null, ecs, null, new());
        using var actions = new DefaultInputActions(null, null, input, config, new Framework.InputActionsConfig { Section = "input" });
        using var types = new DefaultNodeTypes(null, scheduler, ecs, tree, actions, sets);
        using var scenes = new DefaultSceneFiles(null, ecs, types, assets, io);
        types.RegisterType(name: "node");
        var nodes = new NodeWorld(types);
        nodes.Register(new Probe());
        Probe.Readied.Clear();

        var slot = new SceneSlotComponent { Path = "res://scenes/Grouped.scene.toml" };
        types.Spawn(scheduler.Commands(), nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(nodes.Component("scene_slot"), slot)]);
        for (var i = 0; i < 3; i++) scheduler.Tick(1.0f / 60.0f);
        scheduler.Shutdown();

        Assert.Equal([3], Probe.Readied);
    }
}
