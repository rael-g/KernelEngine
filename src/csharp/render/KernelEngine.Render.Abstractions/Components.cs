using System.Numerics;

namespace KernelEngine.Render;

/// <summary>
/// One interleaved mesh vertex: object-space position, normal, texture coordinates and tangent,
/// laid out sequentially as <see cref="IRenderService.UploadMesh"/> uploads them.
/// </summary>
public partial struct MeshVertex
{
    /// <summary>Creates a vertex from its four attributes.</summary>
    public MeshVertex(Vector3 position, Vector3 normal, Vector2 uv, Vector3 tangent)
    {
        Position = position;
        Normal = normal;
        Uv = uv;
        Tangent = tangent;
    }
}
