using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Io.Pool;
using KernelEngine.Runtime;
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
    [Fact]
    public void ANodeOfTheOpenedSceneAndOneOfASceneItInstantiatesAreBothReadied()
    {
        using var pool = new EnkiTaskPool(null, new TaskPool.TaskPoolConfig { WorkerCount = uint.MaxValue });
        using var files = new StdFileSystem(null, new FileSystem.FileSystemConfig { Root = "." });
        using var io = new PoolIo(null, pool, files);
        using var config = new DefaultConfiguration(null);
        using var input = new Input.DefaultInput();
        using var ecs = new FlecsEcsRegistry(null, new Ecs.EcsConfig { ReservedIdCapacity = 1048576 });
        using var runtime = new DefaultRuntime(null, ecs, pool, new Runtime.RuntimeConfig { FixedDt = 1.0f / 60.0f, FixedDtMaxAccum = 0.25f, MaxSystemsPerPhase = 256 });
        using var assets = new DefaultAssetResolver(null, null, null, AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar), io);
        using var tree = new DefaultSceneTree(null, ecs, runtime);
        using var actions = new DefaultInputActions(null, runtime, input, config, new Framework.InputActionsConfig { Section = "input" });
        using var types = new DefaultNodeTypes(null, runtime, ecs, tree, actions);
        using var scenes = new DefaultSceneFiles(null, ecs, types, assets, io);
        var nodes = new NodeWorld(types);
        nodes.Register(new Probe());
        Probe.Readied.Clear();

        var slot = new SceneSlotComponent { Path = "res://scenes/Opened.scene.toml" };
        types.Spawn(runtime.Commands(), nodes.Type("scene_slot"), "Scene", default, [NodeComponent.Of(nodes.Component("scene_slot"), slot)]);
        for (var i = 0; i < 3; i++) runtime.Tick(1.0f / 60.0f);
        runtime.Flush();
        runtime.UnloadModules();

        Assert.Equal([1, 2], Probe.Readied.Order());
    }
}
