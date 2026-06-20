using KernelEngine.Common.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Exposes the raw native scene tree pointer. Implemented by the concrete SceneTree type
/// so that downstream consumers can access the vtable pointer without depending on
/// the SceneTree class directly.
/// </summary>
public unsafe interface INativeSceneTree
{
    ke_scene_tree* Native { get; }
}
