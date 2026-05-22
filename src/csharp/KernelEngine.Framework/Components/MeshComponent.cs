using System.Runtime.InteropServices;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// ECS component linking a scene node to a GPU mesh and a material.
/// Stored contiguously in native memory via <see cref="EcsRegistry"/>.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct MeshComponent
{
    /// <summary>Handle returned by <see cref="Renderer.CreateMesh"/>.</summary>
    public MeshHandle MeshHandle;

    /// <summary>Handle returned by <see cref="Renderer.CreateMaterial"/>.</summary>
    public MaterialHandle MaterialHandle;
}
