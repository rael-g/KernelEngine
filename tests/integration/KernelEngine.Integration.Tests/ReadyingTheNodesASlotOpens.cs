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
        public readonly EngineSchedules Schedules;
        public readonly EngineSets Sets;
        public readonly DefaultScheduler Scheduler;

        public Loop(FlecsEcsRegistry ecs, EnkiJobSystem jobs, EnkiAsync asyncs)
        {
            DefaultSchedule Make() => new(null, ecs, jobs, new ScheduleConfig { RefuseAmbiguity = false });
            Schedules = new EngineSchedules { Startup = Make(), PreUpdate = Make(), Fixed = Make(), Update = Make(), Shutdown = Make() };
            Sets = EngineSets.Register(Schedules);
            Scheduler = new DefaultScheduler(null, jobs, asyncs, new SchedulerConfig { FixedDt = 1.0f / 60.0f, FixedDtMaxAccum = 0.25f });
            Schedules.AddTo(Scheduler);
        }

        public void Attach(Module.Module module) => Schedules.Attach(module, Sets);

        public void Dispose()
        {
            Scheduler.Dispose();
            Schedules.Shutdown.Dispose();
            Schedules.Update.Dispose();
            Schedules.Fixed.Dispose();
            Schedules.PreUpdate.Dispose();
            Schedules.Startup.Dispose();
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
        using var tree = new DefaultSceneTree(null, ecs);
        using var actions = new DefaultInputActions(null, config, new Framework.InputActionsConfig { Section = "input" });
        using var types = new DefaultNodeTypes(null, scheduler, ecs, tree, actions);
        using var nodeSystems = new NodeTypesSystemsModule(null, types);
        loop.Attach(nodeSystems);
        using var scenes = new DefaultSceneFiles(null, ecs, types, assets, io);
        var nodes = new NodeWorld(types);
        nodes.Register(new Probe());
        Probe.Readied.Clear();

        var slot = new SceneSlotComponent { Path = "res://scenes/Opened.scene.toml" };
        types.Spawn(loop.Schedules.PreUpdate.Commands(), nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(nodes.Component("scene_slot"), slot)]);
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
        using var tree = new DefaultSceneTree(null, ecs);
        using var actions = new DefaultInputActions(null, config, new Framework.InputActionsConfig { Section = "input" });
        using var types = new DefaultNodeTypes(null, scheduler, ecs, tree, actions);
        using var nodeSystems = new NodeTypesSystemsModule(null, types);
        loop.Attach(nodeSystems);
        using var scenes = new DefaultSceneFiles(null, ecs, types, assets, io);
        types.RegisterType(name: "node");
        var nodes = new NodeWorld(types);
        nodes.Register(new Probe());
        Probe.Readied.Clear();

        var slot = new SceneSlotComponent { Path = "res://scenes/Grouped.scene.toml" };
        types.Spawn(loop.Schedules.PreUpdate.Commands(), nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(nodes.Component("scene_slot"), slot)]);
        for (var i = 0; i < 3; i++) scheduler.Tick(1.0f / 60.0f);
        scheduler.Shutdown();

        Assert.Equal([3], Probe.Readied);
    }
}
