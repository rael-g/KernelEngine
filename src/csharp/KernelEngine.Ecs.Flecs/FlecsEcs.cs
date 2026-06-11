using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Ecs.Flecs.Native;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Ecs.Flecs;

/// <summary>
/// flecs-backed <see cref="ke_ecs"/> storage. Owns an internal flecs world; satisfies
/// the C ABI ECS contract via the ke_ecs vtable. The vtable methods (component_add,
/// query, etc.) are stubbed in the C plugin until R2.5c — this wrapper exposes only
/// lifetime for now.
/// </summary>
public sealed unsafe class FlecsEcs : IEcs
{
    private ke_ecs* _native;
    private readonly Allocator _allocator;

    public FlecsEcs(Allocator allocator)
    {
        ArgumentNullException.ThrowIfNull(allocator);
        _allocator = allocator;

        ke_ecs_flecs_params @params = default;
        ke_ecs* ecs;
        var rc = KernelEngine.Ecs.Flecs.Native.NativeMethods.ecs_flecs_create(allocator.Native, &@params, &ecs);
        if (rc != ke_result.KE_OK)
            throw new InvalidOperationException($"ke_ecs_flecs_create failed: {rc}");
        _native = ecs;
    }

    /// <summary>
    /// Borrowed pointer to the native ke_ecs vtable. Visible only to friend assemblies
    /// (KernelEngine.Runtime, tests) — game code never sees this. The pointer is alive
    /// until <see cref="Dispose"/> is called.
    /// </summary>
    internal ke_ecs* Native => _native;

    public void Dispose()
    {
        if (_native == null) return;
        _native->destroy(_native);
        _native = null;
    }
}
