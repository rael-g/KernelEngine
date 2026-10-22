using KernelEngine.Common.Native;
using KernelEngine.Ecs.Flecs.Native;

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
    /// <exception cref="OutOfMemoryException">The native factory could not allocate the world.</exception>
    /// <exception cref="InvalidOperationException">flecs could not start the world.</exception>
    public FlecsEcs() : this(null)
    {
    }

    /// <summary>
    /// Creates the native world with the default parameters, the flecs library logging to
    /// <paramref name="logger"/>, or to stderr when it is null.
    /// </summary>
    /// <exception cref="OutOfMemoryException">The native factory could not allocate the world.</exception>
    /// <exception cref="InvalidOperationException">flecs could not start the world.</exception>
    public FlecsEcs(KernelEngine.Logger.ILogger? logger)
    {
        if (logger is not null)
            KernelEngine.Ecs.Flecs.Native.NativeMethods.ecs_flecs_set_log_callback(KernelEngine.Logger.LogCallbackNative.Pointer, KernelEngine.Logger.LogCallbackNative.Pin(logger.Log));
        ke_ecs_flecs_params @params = default;
        ke_ecs_handle handle;
        KernelEngine.NativeResults.ThrowIfFailed(
            KernelEngine.Ecs.Flecs.Native.NativeMethods.ecs_flecs_create(&@params, &handle), "ke_ecs_flecs_create");
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
