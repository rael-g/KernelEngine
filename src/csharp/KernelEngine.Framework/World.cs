using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.Framework.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Managed wrapper over the native <c>ke_world</c> vtable. Aggregates
/// ECS storage, runtime scheduler, and scene tree behind the ke_world ABI;
/// also registers the framework's built-in component apply callbacks.
/// </summary>
/// <remarks>
/// World does NOT own the ecs/runtime/scene_tree it was given — per project
/// doctrine, whoever creates owns. Those resources are destroyed by their own
/// DI wrappers (FlecsEcs, Runtime, etc.). Only the ke_world_state allocation
/// (~300 B) is leaked at shutdown, which the OS reclaims.
/// </remarks>
public sealed unsafe class World : IDisposable
{
    private ke_world* _native;

    /// <summary>Pointer to the native ke_world vtable. Valid until Dispose.</summary>
    public ke_world* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    internal World(ke_world* native) => _native = native;

    /// <summary>Raw ECS storage pointer — valid for the lifetime of the owning IEcs wrapper.</summary>
    public ke_ecs* Ecs => Native->ecs(_native);

    /// <summary>Raw runtime scheduler pointer — valid for the lifetime of the owning IRuntime wrapper.</summary>
    public ke_runtime* Runtime => Native->runtime(_native);

    /// <summary>Raw scene tree pointer — valid for the lifetime of the owning SceneTree wrapper.</summary>
    public ke_scene_tree* NativeSceneTree => Native->scene_tree(_native);

    /// <inheritdoc cref="IDisposable.Dispose"/>
    public void Dispose() => _native = null; // ecs/runtime destroyed by their own DI owners
}
