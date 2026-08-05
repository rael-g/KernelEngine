using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Framework.Native;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using Xunit;

namespace KernelEngine.Runtime.Tests;

// End-to-end coverage for ke_node_host through the C# SDK: a real flecs ECS +
// enkiTS-backed runtime, not a fake — this is the whole point of the design
// (ScriptingArchitectureV3.md §7.14.4), so the dispatch trampoline through
// [UnmanagedCallersOnly] needs a real ke_runtime.Tick() to actually prove out.
public class NodeHostTests : IDisposable
{
    private readonly EnkiScheduler _taskScheduler = new();
    private readonly FlecsEcs _ecs = new();
    private readonly Runtime _runtime;
    private readonly NodeHost _host;

    public unsafe NodeHostTests()
    {
        _runtime = new Runtime(_ecs, _taskScheduler);
        var handle = KernelEngine.Framework.Native.NativeMethods.node_host_create(
            ((INativeEcs)_ecs).Native,
            ((INativeRuntime)_runtime).Native,
            null);
        Assert.True(handle.@ref != null);
        _host = new NodeHost(handle);
    }

    public void Dispose()
    {
        _host.Dispose();
        _runtime.Dispose();
        _ecs.Dispose();
        _taskScheduler.Dispose();
    }

    [Fact]
    public unsafe void Commit_ThenSpawn_CreatesAnEntity()
    {
        using var builder = NodeTypeBuilder.Borrow(_host.BeginType("Simple"));
        Assert.True(builder.Field("speed", ke_variant_type.KE_VARIANT_FLOAT));

        _host.Commit(((INativeNodeTypeBuilder)builder).Native);

        var entity = _host.Spawn("Simple");
        Assert.NotEqual(0ul, entity);
    }

    [Fact]
    public unsafe void Commit_Duplicate_Throws()
    {
        using var builder = NodeTypeBuilder.Borrow(_host.BeginType("Dup"));
        builder.Field("x", ke_variant_type.KE_VARIANT_INT);
        _host.Commit(((INativeNodeTypeBuilder)builder).Native);

        Assert.Throws<KernelError>(() => _host.BeginType("Dup"));
    }

    [Fact]
    public unsafe void RegisteredHook_FiresOnTick_WithTheSpawnedEntity()
    {
        using var builder = NodeTypeBuilder.Borrow(_host.BeginType("Ticking"));
        builder.Field("x", ke_variant_type.KE_VARIANT_INT);
        var hook = builder.Hook(NodeHookKind.Update, (entities, columns, count, dt) =>
        {
            calledWith = entities.Length > 0 ? entities[0] : 0;
            calledCount = count;
            calledDt = dt;
        });
        Assert.NotEqual(0u, hook);
        Assert.True(builder.Access(hook, "Ticking", ke_access.KE_ACCESS_READ | ke_access.KE_ACCESS_WRITE));

        _host.Commit(((INativeNodeTypeBuilder)builder).Native);
        var entity = _host.Spawn("Ticking");

        _runtime.Tick(1f / 60f);

        Assert.Equal(entity, calledWith);
        Assert.Equal(1, calledCount);
        Assert.Equal(1f / 60f, calledDt);
    }

    private ulong calledWith;
    private int calledCount;
    private float calledDt;
}
