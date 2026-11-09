using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Io.Pool;
using KernelEngine.Runtime;
using KernelEngine.TaskPool.Enki;

using Microsoft.Extensions.DependencyInjection;

using Xunit;

namespace KernelEngine.Integration.Tests;

public sealed partial class Probe : Node3D
{
    public static Probe? Last { get; private set; }

    public partial int Kept { get; set; }

    public partial int Given { get; set; }

    public Probe()
    {
        Kept = 7;
        Given = 1;
        Last = this;
    }
}

public class LoadingASceneOverANodeItsCodeBuilt
{
    [Fact]
    public void ANodeTypeGivenOnlyToAddNodeTypeTakesTheKeysItsSectionHoldsAndKeepsTheRestOfItsConstructor()
    {
        using var services = new ServiceCollection()
            .AddFlecsEcsRegistry(worldIdBase: 1048576)
            .AddEnkiTaskPool(workerCount: uint.MaxValue)
            .AddStdFileSystem(root: ".")
            .AddPoolIo()
            .AddAssetResolver()
            .AddNodeType<Probe>()
            .Add<IRuntime, KernelEngine.Runtime.Runtime>()
            .Add<IRuntimeModule>(new FrameworkModule())
            .Add<IRuntimeModule>(new SceneNodesModule(_ => { }))
            .Add<IRuntimeModule>(new SceneRouterModule("Probe"))
            .BuildServiceProvider();
        var runtime = services.GetRequiredService<IRuntime>();
        runtime.LoadModules(services);

        runtime.Tick(1f / 60f);

        var probe = Assert.IsType<Probe>(Probe.Last);
        Assert.Equal(3, probe.Given);
        Assert.Equal(7, probe.Kept);
        runtime.UnloadModules();
    }
}
