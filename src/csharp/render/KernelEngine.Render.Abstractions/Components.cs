using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace KernelEngine.Render;

/// <summary>
/// One interleaved mesh vertex: object-space position plus normal. Matches the
/// vertex layout the render core's forward pass expects (two float3 attributes).
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct MeshVertex
{
    public Vector3 Position;
    public Vector3 Normal;
    public Vector2 UV;
    public Vector3 Tangent;

    public MeshVertex(Vector3 position, Vector3 normal, Vector2 uv, Vector3 tangent)
    {
        Position = position;
        Normal   = normal;
        UV       = uv;
        Tangent  = tangent;
    }
}
