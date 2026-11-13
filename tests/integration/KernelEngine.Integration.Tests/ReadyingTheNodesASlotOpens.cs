using KernelEngine.Async.Enki;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Io.Pool;
using KernelEngine.Job.Enki;
using KernelEngine.Schedule;
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
    sealed class Loop : IDisposable
    {
        public readonly DefaultSchedule First;
        public readonly DefaultSchedule Fixed;
        public readonly DefaultSchedule Main;
        public readonly DefaultScheduler Scheduler;
        public readonly NodeTypesConfig Sets;

        public Loop(FlecsEcsRegistry ecs, EnkiJobSystem jobs, EnkiAsync asyncs)
        {
            First = new DefaultSchedule(null, ecs, jobs, new ScheduleConfig { RefuseAmbiguity = false });
            Fixed = new DefaultSchedule(null, ecs, jobs, new ScheduleConfig { RefuseAmbiguity = false });
            Main = new DefaultSchedule(null, ecs, jobs, new ScheduleConfig { RefuseAmbiguity = false });
            Scheduler = new DefaultScheduler(null, jobs, asyncs, new SchedulerConfig { FixedDt = 1.0f / 60.0f, FixedDtMaxAccum = 0.25f });
            EngineSchedules.Add(Scheduler, First, SchedulerCadence.EveryTick);
            EngineSchedules.Add(Scheduler, Fixed, SchedulerCadence.Fixed);
            EngineSchedules.Add(Scheduler, Main, SchedulerCadence.EveryTick);
            var update = Main.RegisterSet("update", []);
            Sets = new NodeTypesConfig { PreUpdate = First.RegisterSet("pre_update", []), FixedUpdate = Fixed.RegisterSet("fixed_update", []), Update = update, PostUpdate = Main.RegisterSet("post_update", [update]) };
        }

        public void Dispose()
        {
            Scheduler.Dispose();
            Main.Dispose();
            Fixed.Dispose();
            First.Dispose();
        }
    }

    [Fact]
    public void ANodeOfTheOpenedSceneAndOneOfASceneItInstantiatesAreBothReadied()
    {
        using var pool = new EnkiTaskPool(null, new TaskPool.TaskPoolConfig { WorkerCount = uint.MaxValue });
        using var jobs = new EnkiJobSystem(null, new Job.JobSystemConfig { WorkerCount = uint.MaxValue });
        using var asyncs = new EnkiAsync(null, new Async.AsyncConfig { WorkerCount = 1, SubmitCapacity = 16 });
        using var files = new StdFileSystem(null, new FileSystem.FileSystemConfig { Root = "." });
        using var io = new PoolIo(null, pool, files);
        using var config = new DefaultConfiguration(null);
        using var input = new Input.DefaultInput();
        using var ecs = new FlecsEcsRegistry(null, new Ecs.EcsConfig { ReservedIdCapacity = 1048576 });
        using var loop = new Loop(ecs, jobs, asyncs);
        var scheduler = loop.Scheduler;
        using var assets = new DefaultAssetResolver(null, null, null, AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar), io);
        using var tree = new DefaultSceneTree(null, ecs, null, new());
        using var actions = new DefaultInputActions(null, null, input, config, new Framework.InputActionsConfig { Section = "input" });
        using var types = new DefaultNodeTypes(null, scheduler, loop.First, loop.Fixed, loop.Main, ecs, tree, actions, loop.Sets);
        using var scenes = new DefaultSceneFiles(null, ecs, types, assets, io);
        var nodes = new NodeWorld(types);
        nodes.Register(new Probe());
        Probe.Readied.Clear();

        var slot = new SceneSlotComponent { Path = "res://scenes/Opened.scene.toml" };
        types.Spawn(loop.First.Commands(), nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(nodes.Component("scene_slot"), slot)]);
        for (var i = 0; i < 3; i++) scheduler.Tick(1.0f / 60.0f);
        scheduler.Shutdown();

        Assert.Equal([1, 2], Probe.Readied.Order());
    }

    [Fact]
    public void A_scene_places_nodes_under_a_bare_node_that_carries_no_component()
    {
        using var pool = new EnkiTaskPool(null, new TaskPool.TaskPoolConfig { WorkerCount = uint.MaxValue });
        using var jobs = new EnkiJobSystem(null, new Job.JobSystemConfig { WorkerCount = uint.MaxValue });
        using var asyncs = new EnkiAsync(null, new Async.AsyncConfig { WorkerCount = 1, SubmitCapacity = 16 });
        using var files = new StdFileSystem(null, new FileSystem.FileSystemConfig { Root = "." });
        using var io = new PoolIo(null, pool, files);
        using var config = new DefaultConfiguration(null);
        using var input = new Input.DefaultInput();
        using var ecs = new FlecsEcsRegistry(null, new Ecs.EcsConfig { ReservedIdCapacity = 1048576 });
        using var loop = new Loop(ecs, jobs, asyncs);
        var scheduler = loop.Scheduler;
        using var assets = new DefaultAssetResolver(null, null, null, AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar), io);
        using var tree = new DefaultSceneTree(null, ecs, null, new());
        using var actions = new DefaultInputActions(null, null, input, config, new Framework.InputActionsConfig { Section = "input" });
        using var types = new DefaultNodeTypes(null, scheduler, loop.First, loop.Fixed, loop.Main, ecs, tree, actions, loop.Sets);
        using var scenes = new DefaultSceneFiles(null, ecs, types, assets, io);
        types.RegisterType(name: "node");
        var nodes = new NodeWorld(types);
        nodes.Register(new Probe());
        Probe.Readied.Clear();

        var slot = new SceneSlotComponent { Path = "res://scenes/Grouped.scene.toml" };
        types.Spawn(loop.First.Commands(), nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(nodes.Component("scene_slot"), slot)]);
        for (var i = 0; i < 3; i++) scheduler.Tick(1.0f / 60.0f);
        scheduler.Shutdown();

        Assert.Equal([3], Probe.Readied);
    }
}
