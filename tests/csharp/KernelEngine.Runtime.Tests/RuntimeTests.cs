using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.Runtime;
using Xunit;

namespace KernelEngine.Runtime.Tests;

// Managed coverage for the split Runtime + FlecsEcs + TaskScheduler triple.
// Mirrors the C++ RuntimeSpike suite in tests/integration/cpp/test_runtime.cpp.
public class RuntimeTests : IDisposable
{
    private readonly MallocAllocator _allocator = new();
    private readonly KernelEngine.Kernel.TaskScheduler _taskScheduler;
    private readonly FlecsEcs        _ecs;

    public unsafe RuntimeTests()
    {
        ke_task_scheduler* nativeScheduler;
        var rc = KernelEngine.TaskScheduler.Enki.Native.NativeMethods.task_scheduler_enki_create(
            _allocator.Native, &nativeScheduler);
        if (rc != ke_result.KE_OK)
            throw new InvalidOperationException($"task_scheduler_enki_create failed: {rc}");
        _taskScheduler = new KernelEngine.Kernel.TaskScheduler(nativeScheduler);
        _ecs           = new FlecsEcs(_allocator);
    }

    public void Dispose()
    {
        _ecs.Dispose();
        _taskScheduler.Dispose();
        _allocator.Dispose();
    }

    [Fact]
    public void Create_Tick_Destroy_NoSystems()
    {
        using var runtime = new Runtime(_allocator, _ecs, _taskScheduler);
        runtime.Tick(1f / 60f);
    }

    [Fact]
    public void RegisterModule_InvokesOnLoad_Once()
    {
        using var runtime = new Runtime(_allocator, _ecs, _taskScheduler);
        var loadCount = 0;
        var id = runtime.RegisterModule("TestModule", _ => loadCount++);
        Assert.NotEqual(0u, id);
        Assert.Equal(1, loadCount);
    }

    [Fact]
    public void RegisteredSystem_FiresOncePerTick()
    {
        using var runtime = new Runtime(_allocator, _ecs, _taskScheduler);
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
        using var runtime = new Runtime(_allocator, _ecs, _taskScheduler);
        var calls = 0;
        runtime.RegisterSystem("Bare", RuntimePhase.Update, (_, _) => calls++);
        runtime.Tick(0.016f);
        runtime.Tick(0.016f);
        Assert.Equal(2, calls);
    }

    [Fact]
    public void SystemException_PropagatesAtTick()
    {
        using var runtime = new Runtime(_allocator, _ecs, _taskScheduler);
        runtime.RegisterSystem("Boom", RuntimePhase.Update,
            (_, _) => throw new InvalidOperationException("kaboom"));

        var ex = Assert.Throws<InvalidOperationException>(() => runtime.Tick(0.016f));
        Assert.Equal("System execution threw", ex.Message);
        Assert.NotNull(ex.InnerException);
        Assert.Equal("kaboom", ex.InnerException!.Message);
    }

    [Fact]
    public void Dispose_IsIdempotent()
    {
        var runtime = new Runtime(_allocator, _ecs, _taskScheduler);
        runtime.Dispose();
        runtime.Dispose();
    }

    [Fact]
    public void OperationsAfterDispose_Throw()
    {
        var runtime = new Runtime(_allocator, _ecs, _taskScheduler);
        runtime.Dispose();
        Assert.Throws<ObjectDisposedException>(() => runtime.Tick(0.016f));
    }

    [Fact]
    public void Constructor_NullEcs_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => new Runtime(_allocator, null!, _taskScheduler));
    }

    [Fact]
    public void Constructor_NullAllocator_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => new Runtime(null!, _ecs, _taskScheduler));
    }
}
