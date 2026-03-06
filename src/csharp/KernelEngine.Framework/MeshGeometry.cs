using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Built-in mesh geometry definitions. Use these to create GPU meshes via <see cref="Renderer.CreateMesh"/>.
/// </summary>
public static class MeshGeometry
{
    /// <summary>Unit quad on the XY plane, centered at origin (-0.5..+0.5), normal pointing +Z.</summary>
    // Normal=(0,0,1) Tangent=(1,0,0) → Bitangent=cross(N,T)*1=(0,1,0)
    public static readonly ke_vertex[] QuadVertices =
    [
        new() { x = -0.5f, y = -0.5f, z = 0f, nx = 0f, ny = 0f, nz = 1f, u = 0f, v = 0f, tx = 1f, ty = 0f, tz = 0f, tw = 1f },
        new() { x =  0.5f, y = -0.5f, z = 0f, nx = 0f, ny = 0f, nz = 1f, u = 1f, v = 0f, tx = 1f, ty = 0f, tz = 0f, tw = 1f },
        new() { x =  0.5f, y =  0.5f, z = 0f, nx = 0f, ny = 0f, nz = 1f, u = 1f, v = 1f, tx = 1f, ty = 0f, tz = 0f, tw = 1f },
        new() { x = -0.5f, y =  0.5f, z = 0f, nx = 0f, ny = 0f, nz = 1f, u = 0f, v = 1f, tx = 1f, ty = 0f, tz = 0f, tw = 1f },
    ];

    /// <summary>Index buffer for <see cref="QuadVertices"/>.</summary>
    public static readonly ushort[] QuadIndices = [0, 1, 2, 0, 2, 3];
}
