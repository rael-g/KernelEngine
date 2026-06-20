using KernelEngine.Ecs.Flecs.Native;
using KernelEngine.Kernel;
using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Flecs;

/// <summary>
/// flecs-backed <see cref="ke_ecs"/> storage. Owns an internal flecs world; satisfies
/// the C ABI ECS contract via the ke_ecs vtable.
/// </summary>
public sealed unsafe class FlecsEcs : IEcs, INativeEcs
{
    private ke_ecs* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_ecs*, void> _destroy;

    public FlecsEcs()
    {
        ke_ecs_flecs_params @params = default;
        var handle = KernelEngine.Ecs.Flecs.Native.NativeMethods.ecs_flecs_create(&@params, null);
        if (handle.@ref == null)
            throw new InvalidOperationException("ke_ecs_flecs_create failed");
        _native = handle.@ref;
        _destroy = handle.destroy;
    }

    ke_ecs* INativeEcs.Native => _native;

    public void Dispose()
    {
        if (_native == null) return;
        if (_destroy != null) _destroy(_native);
        _native = null;
    }
}
