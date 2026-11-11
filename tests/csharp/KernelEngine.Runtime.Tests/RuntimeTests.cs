using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;
using KernelEngine.TaskPool.Enki;

using Xunit;

namespace KernelEngine.Runtime.Tests;

public class RuntimeTests : IDisposable
{
    private static readonly RuntimeConfig SixtyPerSecond = new() { FixedDt = 1f / 60f, FixedDtMaxAccum = 0.25f, MaxSystemsPerPhase = 256 };

    private readonly EnkiTaskPool _taskPool = new(new TaskPoolConfig { WorkerCount = uint.MaxValue });
    private readonly FlecsEcsRegistry _ecs = new(new EcsConfig { ReservedIdCapacity = 1048576 });

    public void Dispose()
    {
        _ecs.Dispose();
        _taskPool.Dispose();
    }

    [Fact]
    public void Create_Tick_Destroy_NoSystems()
    {
        using IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        runtime.Tick(1f / 60f);
    }

    [Fact]
    public void Dispose_OfItsDependenciesFirst_LeavesTheRuntimeUsableUntilItIsDisposed()
    {
        var ecs = new FlecsEcsRegistry(new EcsConfig { ReservedIdCapacity = 1048576 });
        var taskPool = new EnkiTaskPool(new TaskPoolConfig { WorkerCount = uint.MaxValue });
        IRuntime runtime = new DefaultRuntime(ecs, taskPool, SixtyPerSecond);
        var unloadCount = 0;
        runtime.RegisterModule("UnloadModule", _ => { }, _ => unloadCount++);

        ecs.Dispose();
        taskPool.Dispose();
        runtime.Tick(1f / 60f);
        runtime.Dispose();

        Assert.Equal(1, unloadCount);
        Assert.True(((KernelEngine.Ecs.INativeEcs)ecs).Owner!.IsClosed);
        Assert.True(((KernelEngine.TaskPool.INativeTaskPool)taskPool).Owner!.IsClosed);
    }

    [Fact]
    public void RegisterModule_InvokesOnLoad_Once()
    {
        using IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        var loadCount = 0;
        var id = runtime.RegisterModule("TestModule", _ => loadCount++);
        Assert.NotEqual(0u, id);
        Assert.Equal(1, loadCount);
    }

    [Fact]
    public void RegisterModule_InvokesOnUnload_WhenRuntimeIsDisposed()
    {
        IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        var unloadCount = 0;
        runtime.RegisterModule("UnloadModule", _ => { }, _ => unloadCount++);
        Assert.Equal(0, unloadCount);

        runtime.Dispose();

        Assert.Equal(1, unloadCount);
    }

    [Fact]
    public void RegisterModule_UnloadsInReverseRegistrationOrder()
    {
        IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        var order = new List<string>();
        runtime.RegisterModule("First", _ => { }, _ => order.Add("First"));
        runtime.RegisterModule("Second", _ => { }, _ => order.Add("Second"));

        runtime.Dispose();

        Assert.Equal(["Second", "First"], order);
    }

    [Fact]
    public void RegisteredSystem_FiresOncePerTick()
    {
        using IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        var tickCount = 0;
        runtime.RegisterModule("TickModule", rt =>
        {
            rt.RegisterSystem("TickCounter", RuntimePhase.Update, (_, _) => tickCount++);
        });

        for (int i = 0; i < 10; i++)
            runtime.Tick(1f / 60f);

        Assert.Equal(10, tickCount);
    }

    [Fact]
    public void RegisterSystem_DirectlyFromCallerCode_Works()
    {
        using IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        var calls = 0;
        runtime.RegisterSystem("Bare", RuntimePhase.Update, (_, _) => calls++);
        runtime.Tick(0.016f);
        runtime.Tick(0.016f);
        Assert.Equal(2, calls);
    }

    [Fact]
    public void SystemException_PropagatesAtTick()
    {
        using IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        runtime.RegisterSystem("Boom", RuntimePhase.Update,
            (_, _) => throw new InvalidOperationException("kaboom"));

        var ex = Assert.Throws<InvalidOperationException>(() => runtime.Tick(0.016f));
        Assert.Equal("A handler registered with this provider threw", ex.Message);
        Assert.NotNull(ex.InnerException);
        Assert.Equal("kaboom", ex.InnerException!.Message);
    }

    [Fact]
    public void SystemException_StopsTheRestOfTheTick()
    {
        using IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        var laterRan = false;
        runtime.RegisterSystem("Boom", RuntimePhase.PreUpdate,
            (_, _) => throw new InvalidOperationException("kaboom"));
        runtime.RegisterSystem("Later", RuntimePhase.PostUpdate, (_, _) => laterRan = true);

        Assert.Throws<InvalidOperationException>(() => runtime.Tick(0.016f));

        Assert.False(laterRan);
    }

    [Fact]
    public void RenderSystemException_SurvivesTheTickThatDispatchedIt()
    {
        using IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        using var released = new ManualResetEventSlim(false);

        runtime.RegisterSystem("BoomRender", RuntimePhase.Render, (_, _) =>
        {
            released.Wait();
            throw new InvalidOperationException("render kaboom");
        });

        runtime.Tick(0.016f);
        released.Set();

        var ex = Assert.Throws<InvalidOperationException>(() => runtime.Flush());
        Assert.Equal("render kaboom", ex.InnerException!.Message);
    }

    [Fact]
    public void EverySystemThatThrowsIsReported_NotJustTheLast()
    {
        using IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        runtime.RegisterSystem("BoomA", RuntimePhase.Update,
            (_, _) => throw new InvalidOperationException("a"));
        runtime.RegisterSystem("BoomB", RuntimePhase.Update,
            (_, _) => throw new InvalidOperationException("b"));

        var ex = Assert.Throws<InvalidOperationException>(() => runtime.Tick(0.016f));
        var aggregate = Assert.IsType<AggregateException>(ex.InnerException);
        Assert.Equal(["a", "b"], aggregate.InnerExceptions.Select(e => e.Message).Order());
    }

    [Fact]
    public void Dispose_IsIdempotent()
    {
        IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        runtime.Dispose();
        runtime.Dispose();
    }

    [Fact]
    public void OperationsAfterDispose_Throw()
    {
        IRuntime runtime = new DefaultRuntime(_ecs, _taskPool, SixtyPerSecond);
        runtime.Dispose();
        Assert.Throws<ObjectDisposedException>(() => runtime.Tick(0.016f));
    }

    [Fact]
    public void Constructor_NullEcs_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => new DefaultRuntime(null!, _taskPool, SixtyPerSecond));
    }

    [Fact]
    public void Constructor_NullAllocator_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => new DefaultRuntime(_ecs, null!, SixtyPerSecond));
    }
}
