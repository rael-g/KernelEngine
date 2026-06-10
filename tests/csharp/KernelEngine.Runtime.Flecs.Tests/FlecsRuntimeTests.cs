using KernelEngine.Kernel;
using KernelEngine.Runtime.Flecs;
using Xunit;

namespace KernelEngine.Runtime.Flecs.Tests;

// Spike-level managed coverage for FlecsRuntime — mirrors the C++ test_runtime_flecs
// suite from tests/integration/cpp/. Validates the bindings cross the ABI cleanly,
// the trampolines reach managed callbacks, and exceptions surface back at tick().
public class FlecsRuntimeTests : IDisposable
{
    private readonly MallocAllocator _allocator = new();

    public void Dispose() => _allocator.Dispose();

    [Fact]
    public void Create_Tick_Destroy_NoSystems()
    {
        using var runtime = new FlecsRuntime(_allocator);
        runtime.Tick(1f / 60f);  // no-op; just proves the wrapper holds together
    }

    [Fact]
    public void RegisterModule_InvokesOnLoad_Once()
    {
        using var runtime = new FlecsRuntime(_allocator);
        var loadCount = 0;
        var id = runtime.RegisterModule("TestModule", _ => loadCount++);
        Assert.NotEqual(0u, id);
        Assert.Equal(1, loadCount);
    }

    [Fact]
    public void RegisteredSystem_FiresOncePerTick()
    {
        using var runtime = new FlecsRuntime(_allocator);
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
        // Bypass the module pattern; register a system from the host directly.
        // Real games go through modules, but this exercises the bare ABI path.
        using var runtime = new FlecsRuntime(_allocator);
        var calls = 0;
        runtime.RegisterSystem("Bare", RuntimePhase.Update, (_, _) => calls++);
        runtime.Tick(0.016f);
        runtime.Tick(0.016f);
        Assert.Equal(2, calls);
    }

    [Fact]
    public void SystemException_PropagatesAtTick()
    {
        using var runtime = new FlecsRuntime(_allocator);
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
        var runtime = new FlecsRuntime(_allocator);
        runtime.Dispose();
        runtime.Dispose();  // must not throw or double-free
    }

    [Fact]
    public void OperationsAfterDispose_Throw()
    {
        var runtime = new FlecsRuntime(_allocator);
        runtime.Dispose();
        Assert.Throws<ObjectDisposedException>(() => runtime.Tick(0.016f));
    }

    [Fact]
    public void Constructor_NullAllocator_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => new FlecsRuntime(null!));
    }
}
