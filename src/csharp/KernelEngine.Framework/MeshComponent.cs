using System.Runtime.InteropServices;

namespace KernelEngine.Framework;

/// <summary>
/// ECS component holding the render color for a mesh node.
/// Stored contiguously in native memory via <see cref="EcsRegistry"/>.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct MeshComponent
{
    public float R, G, B, A;
}
