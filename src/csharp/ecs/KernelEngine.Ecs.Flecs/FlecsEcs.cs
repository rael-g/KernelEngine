using KernelEngine.Ecs.Flecs.Native;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Ecs.Flecs;

/// <summary>
/// flecs-backed <see cref="ke_ecs"/> storage. Owns an internal flecs world; satisfies
/// the C ABI ECS contract via the ke_ecs vtable.
/// </summary>
public sealed unsafe class FlecsEcs : IEcs
{
    private ke_ecs* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_ecs*, void> _destroy;

    public FlecsEcs()
    {
        ke_ecs_flecs_params @params = default;
        ke_ecs_handle handle;
        var rc = KernelEngine.Ecs.Flecs.Native.NativeMethods.ecs_flecs_create(&@params, &handle, null);
        if (rc != (int)ke_result.KE_OK)
            throw new InvalidOperationException($"ke_ecs_flecs_create failed: {(ke_result)rc}");
        _native = handle.@ref;
        _destroy = handle.destroy;
    }

    /// <summary>
    /// Borrowed pointer to the native ke_ecs vtable. The pointer is alive until
    /// <see cref="Dispose"/> is called.
    /// </summary>
    public ke_ecs* Native => _native;

    public void Dispose()
    {
        if (_native == null) return;
        if (_destroy != null) _destroy(_native);
        _native = null;
    }
}
