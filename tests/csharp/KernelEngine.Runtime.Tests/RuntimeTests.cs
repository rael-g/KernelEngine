using KernelEngine.Ecs.Flecs;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using Xunit;

namespace KernelEngine.Runtime.Tests;

public class RuntimeTests : IDisposable
{
    private readonly EnkiScheduler _taskScheduler = new();
    private readonly FlecsEcs          _ecs           = new();

    public void Dispose()
    {
        _ecs.Dispose();
        _taskScheduler.Dispose();
    }

    [Fact]
    public void Create_Tick_Destroy_NoSystems()
    {
        using IRuntime runtime = new Runtime(_ecs, _taskScheduler);
        runtime.Tick(1f / 60f);
    }

    [Fact]
    public void RegisterModule_InvokesOnLoad_Once()
    {
        using IRuntime runtime = new Runtime(_ecs, _taskScheduler);
        var loadCount = 0;
        var id = runtime.RegisterModule("TestModule", _ => loadCount++);
        Assert.NotEqual(0u, id);
        Assert.Equal(1, loadCount);
    }

    [Fact]
    public void RegisterModule_InvokesOnUnload_WhenRuntimeIsDisposed()
    {
        IRuntime runtime = new Runtime(_ecs, _taskScheduler);
        var unloadCount = 0;
        runtime.RegisterModule("UnloadModule", _ => { }, _ => unloadCount++);
        Assert.Equal(0, unloadCount);

        runtime.Dispose();

        Assert.Equal(1, unloadCount);
    }

    [Fact]
    public void RegisterModule_UnloadsInReverseRegistrationOrder()
    {
        IRuntime runtime = new Runtime(_ecs, _taskScheduler);
        var order = new List<string>();
        runtime.RegisterModule("First", _ => { }, _ => order.Add("First"));
        runtime.RegisterModule("Second", _ => { }, _ => order.Add("Second"));

        runtime.Dispose();

        Assert.Equal(["Second", "First"], order);
    }

    [Fact]
    public void RegisteredSystem_FiresOncePerTick()
    {
        using IRuntime runtime = new Runtime(_ecs, _taskScheduler);
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
        using IRuntime runtime = new Runtime(_ecs, _taskScheduler);
        var calls = 0;
        runtime.RegisterSystem("Bare", RuntimePhase.Update, (_, _) => calls++);
        runtime.Tick(0.016f);
        runtime.Tick(0.016f);
        Assert.Equal(2, calls);
    }

    [Fact]
    public void SystemException_PropagatesAtTick()
    {
        using IRuntime runtime = new Runtime(_ecs, _taskScheduler);
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
        using IRuntime runtime = new Runtime(_ecs, _taskScheduler);
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
        using IRuntime runtime = new Runtime(_ecs, _taskScheduler);
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
        using IRuntime runtime = new Runtime(_ecs, _taskScheduler);
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
        IRuntime runtime = new Runtime(_ecs, _taskScheduler);
        runtime.Dispose();
        runtime.Dispose();
    }

    [Fact]
    public void OperationsAfterDispose_Throw()
    {
        IRuntime runtime = new Runtime(_ecs, _taskScheduler);
        runtime.Dispose();
        Assert.Throws<ObjectDisposedException>(() => runtime.Tick(0.016f));
    }

    [Fact]
    public void Constructor_NullEcs_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => new Runtime(null!, _taskScheduler));
    }

    [Fact]
    public void Constructor_NullAllocator_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => new Runtime(_ecs, null!));
    }
}
