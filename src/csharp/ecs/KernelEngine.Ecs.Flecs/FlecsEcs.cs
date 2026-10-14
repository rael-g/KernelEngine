using KernelEngine.Ecs.Flecs.Native;
using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Flecs;

/// <summary>
/// flecs-backed <see cref="ke_ecs"/> storage. Owns the native world it creates and destroys it on
/// dispose.
/// </summary>
public sealed unsafe class FlecsEcs : IDisposable, INativeEcs
{
    private ke_ecs* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_ecs*, void> _destroy;

    /// <summary>Creates the native world with the default parameters.</summary>
    /// <exception cref="InvalidOperationException">The native factory returned no world.</exception>
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

    /// <summary>Destroys the native world. Safe to call more than once.</summary>
    public void Dispose()
    {
        if (_native == null) return;
        if (_destroy != null) _destroy(_native);
        _native = null;
    }
}
