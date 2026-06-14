using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper over the native <c>ke_world</c> vtable. Aggregates
/// ECS storage, runtime scheduler, and scene tree behind the ke_world ABI.
/// </summary>
/// <remarks>
/// World does NOT own the ecs/runtime/scene_tree it was given — per project
/// doctrine, whoever creates owns. Those resources are destroyed by their own
/// DI wrappers (FlecsEcs, Runtime, etc.). Only the ke_world_state allocation
/// is leaked at shutdown, which the OS reclaims.
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

    /// <summary>Creates a World wrapper around an already-created ke_world pointer.</summary>
    public World(ke_world* native) => _native = native;

    /// <summary>Raw ECS storage pointer — valid for the lifetime of the owning IEcs wrapper.</summary>
    public ke_ecs* Ecs => Native->ecs(_native);

    /// <summary>Raw runtime scheduler pointer — valid for the lifetime of the owning IRuntime wrapper.</summary>
    public ke_runtime* Runtime => Native->runtime(_native);

    /// <summary>Raw scene tree pointer — valid for the lifetime of the owning SceneTree wrapper.</summary>
    public ke_scene_tree* NativeSceneTree => Native->scene_tree(_native);

    private SceneTree? _sceneTree;

    /// <summary>
    /// Managed wrapper over the scene tree owned by this world.
    /// Created once on first access; backed by <see cref="NativeSceneTree"/>.
    /// </summary>
    public SceneTree SceneTree => _sceneTree ??= new SceneTree(NativeSceneTree);

    /// <inheritdoc cref="IDisposable.Dispose"/>
    public void Dispose() => _native = null; // ecs/runtime destroyed by their own DI owners
}
