using System.Numerics;

namespace KernelEngine.Render;

/// <summary>
/// Procedural mesh factories for the v2 render path. Each call uploads vertex +
/// index buffers through an <see cref="IRenderResources"/> and returns a handle.
/// Call from the render worker (GPU upload has thread affinity).
/// </summary>
public static class MeshPrimitives
{
    /// <summary>Unit XY quad centered at the origin, facing +Z.</summary>
    public static MeshHandle Quad(IRenderResources resources)
    {
        ReadOnlySpan<MeshVertex> verts = stackalloc MeshVertex[]
        {
            new(new(-0.5f, -0.5f, 0f), new(0, 0, 1), new(0, 1)),
            new(new( 0.5f, -0.5f, 0f), new(0, 0, 1), new(1, 1)),
            new(new( 0.5f,  0.5f, 0f), new(0, 0, 1), new(1, 0)),
            new(new(-0.5f,  0.5f, 0f), new(0, 0, 1), new(0, 0)),
        };
        ReadOnlySpan<ushort> indices = stackalloc ushort[] { 0, 1, 2, 0, 2, 3 };
        return resources.UploadMesh(verts, indices);
    }

    /// <summary>Unit cube centered at the origin, 24 verts (4 per face).</summary>
    public static MeshHandle Cube(IRenderResources resources)
    {
        const float h = 0.5f;
        Span<MeshVertex> verts = stackalloc MeshVertex[24];
        Span<ushort> idx       = stackalloc ushort[36];

        static void Face(Span<MeshVertex> verts, Span<ushort> idx, int f, Vector3 n,
                         Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3)
        {
            int v = f * 4;
            verts[v + 0] = new(p0, n, new(0, 1));
            verts[v + 1] = new(p1, n, new(1, 1));
            verts[v + 2] = new(p2, n, new(1, 0));
            verts[v + 3] = new(p3, n, new(0, 0));
            int i = f * 6;
            idx[i + 0] = (ushort)(v + 0); idx[i + 1] = (ushort)(v + 1); idx[i + 2] = (ushort)(v + 2);
            idx[i + 3] = (ushort)(v + 0); idx[i + 4] = (ushort)(v + 2); idx[i + 5] = (ushort)(v + 3);
        }

        Face(verts, idx, 0, new( 1, 0, 0), new(+h, -h, +h), new(+h, -h, -h), new(+h, +h, -h), new(+h, +h, +h));
        Face(verts, idx, 1, new(-1, 0, 0), new(-h, -h, -h), new(-h, -h, +h), new(-h, +h, +h), new(-h, +h, -h));
        Face(verts, idx, 2, new( 0, 1, 0), new(-h, +h, +h), new(+h, +h, +h), new(+h, +h, -h), new(-h, +h, -h));
        Face(verts, idx, 3, new( 0,-1, 0), new(-h, -h, -h), new(+h, -h, -h), new(+h, -h, +h), new(-h, -h, +h));
        Face(verts, idx, 4, new( 0, 0, 1), new(-h, -h, +h), new(+h, -h, +h), new(+h, +h, +h), new(-h, +h, +h));
        Face(verts, idx, 5, new( 0, 0,-1), new(+h, -h, -h), new(-h, -h, -h), new(-h, +h, -h), new(+h, +h, -h));

        return resources.UploadMesh(verts, idx);
    }
}
