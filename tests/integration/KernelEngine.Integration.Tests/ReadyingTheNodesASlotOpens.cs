using KernelEngine.Async.Enki;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Io.Std;
using KernelEngine.Job.Enki;
using KernelEngine.Schedule;
using KernelEngine.Scheduler;

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

        public Loop(FlecsEcsRegistry ecs, EnkiJobSystem jobs, EnkiAsync asyncs, DefaultConfiguration config)
        {
            DefaultSchedule Make() => new(ecs, jobs, config.Section("schedule"));
            Schedules = new EngineSchedules { Startup = Make(), PreUpdate = Make(), Fixed = Make(), Update = Make(), Shutdown = Make() };
            Sets = EngineSets.Register(Schedules);
            Scheduler = new DefaultScheduler(jobs, asyncs, config.Section("scheduler"));
            Schedules.AddTo(Scheduler);
        }

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
        using var config = new DefaultConfiguration();
        using var jobs = new EnkiJobSystem(config.Section("job"));
        using var asyncs = new EnkiAsync(config.Section("async"));
        using var files = new StdFileSystem(AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar));
        using var io = new StdIo(files, config.Section("io"));
        using var input = new Input.DefaultInput();
        using var ecs = new FlecsEcsRegistry(config.Section("ecs"));
        using var loop = new Loop(ecs, jobs, asyncs, config);
        var scheduler = loop.Scheduler;
        using var assets = new DefaultAssetResolver(null, null, io);
        using var tree = new DefaultSceneTree(ecs);
        using var actions = new DefaultInputActions(config.Section("input"));
        using var types = new DefaultNodeTypes(scheduler, ecs, tree, actions);
        using var nodeSystems = new NodeTypesSystems(types, loop.Schedules.PreUpdate, loop.Sets.PreUpdate, loop.Schedules.Fixed, loop.Sets.FixedUpdate,
            loop.Schedules.Update, loop.Sets.Update, loop.Schedules.Update, loop.Sets.PostUpdate);
        using var scenes = new DefaultSceneFiles(ecs, types, assets, io, loop.Schedules.Startup, loop.Sets.Startup, config.Section("scene_files"));
        var nodes = new NodeWorld(types);
        nodes.Register(new Probe());
        Probe.Readied.Clear();

        var slot = new SceneSlotComponent { Path = "res://scenes/Opened.scene.toml" };
        types.Spawn(loop.Schedules.PreUpdate.Commands(), nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(nodes.Component("scene_slot"), slot)]);
        for (var i = 0; i < 10 && Probe.Readied.Count == 0; i++) scheduler.Tick(1.0f / 60.0f);
        scheduler.Tick(1.0f / 60.0f);
        scheduler.Shutdown();

        Assert.Equal([1, 2], Probe.Readied.Order());
    }

    [Fact]
    public void A_scene_places_nodes_under_a_bare_node_that_carries_no_component()
    {
        using var config = new DefaultConfiguration();
        using var jobs = new EnkiJobSystem(config.Section("job"));
        using var asyncs = new EnkiAsync(config.Section("async"));
        using var files = new StdFileSystem(AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar));
        using var io = new StdIo(files, config.Section("io"));
        using var input = new Input.DefaultInput();
        using var ecs = new FlecsEcsRegistry(config.Section("ecs"));
        using var loop = new Loop(ecs, jobs, asyncs, config);
        var scheduler = loop.Scheduler;
        using var assets = new DefaultAssetResolver(null, null, io);
        using var tree = new DefaultSceneTree(ecs);
        using var actions = new DefaultInputActions(config.Section("input"));
        using var types = new DefaultNodeTypes(scheduler, ecs, tree, actions);
        using var nodeSystems = new NodeTypesSystems(types, loop.Schedules.PreUpdate, loop.Sets.PreUpdate, loop.Schedules.Fixed, loop.Sets.FixedUpdate,
            loop.Schedules.Update, loop.Sets.Update, loop.Schedules.Update, loop.Sets.PostUpdate);
        using var scenes = new DefaultSceneFiles(ecs, types, assets, io, loop.Schedules.Startup, loop.Sets.Startup, config.Section("scene_files"));
        types.RegisterType(name: "node");
        var nodes = new NodeWorld(types);
        nodes.Register(new Probe());
        Probe.Readied.Clear();

        var slot = new SceneSlotComponent { Path = "res://scenes/Grouped.scene.toml" };
        types.Spawn(loop.Schedules.PreUpdate.Commands(), nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(nodes.Component("scene_slot"), slot)]);
        for (var i = 0; i < 10 && Probe.Readied.Count == 0; i++) scheduler.Tick(1.0f / 60.0f);
        scheduler.Tick(1.0f / 60.0f);
        scheduler.Shutdown();

        Assert.Equal([3], Probe.Readied);
    }
}
