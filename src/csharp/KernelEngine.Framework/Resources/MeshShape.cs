using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A CPU-side mesh descriptor (vertices + indices) ready to be uploaded by
/// <see cref="ResourceManager.CreateMeshAsync(MeshShape)"/>. Static factories produce common
/// primitives so game code doesn't hand-build them.
/// </summary>
public sealed record MeshShape(Vertex[] Vertices, ushort[] Indices)
{
    /// <summary>
    /// Unit cube centered at the origin, 24 vertices (4 per face) so each face has its own
    /// normal/UVs — what shaders + SSAO need (per-face flat shading, no shared edges).
    /// </summary>
    public static MeshShape Cube()
    {
        var v = new List<Vertex>(24);
        void Face(Vector3 n, Vector3 t, Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3)
        {
            v.Add(new Vertex { X = p0.X, Y = p0.Y, Z = p0.Z, Nx = n.X, Ny = n.Y, Nz = n.Z, U = 0, V = 0, Tx = t.X, Ty = t.Y, Tz = t.Z, Tw = 1 });
            v.Add(new Vertex { X = p1.X, Y = p1.Y, Z = p1.Z, Nx = n.X, Ny = n.Y, Nz = n.Z, U = 1, V = 0, Tx = t.X, Ty = t.Y, Tz = t.Z, Tw = 1 });
            v.Add(new Vertex { X = p2.X, Y = p2.Y, Z = p2.Z, Nx = n.X, Ny = n.Y, Nz = n.Z, U = 1, V = 1, Tx = t.X, Ty = t.Y, Tz = t.Z, Tw = 1 });
            v.Add(new Vertex { X = p3.X, Y = p3.Y, Z = p3.Z, Nx = n.X, Ny = n.Y, Nz = n.Z, U = 0, V = 1, Tx = t.X, Ty = t.Y, Tz = t.Z, Tw = 1 });
        }
        Face(new(1, 0, 0), new(0, 0, -1), new(0.5f, -0.5f, 0.5f), new(0.5f, -0.5f, -0.5f), new(0.5f, 0.5f, -0.5f), new(0.5f, 0.5f, 0.5f));
        Face(new(-1, 0, 0), new(0, 0, 1), new(-0.5f, -0.5f, -0.5f), new(-0.5f, -0.5f, 0.5f), new(-0.5f, 0.5f, 0.5f), new(-0.5f, 0.5f, -0.5f));
        Face(new(0, 1, 0), new(1, 0, 0), new(-0.5f, 0.5f, 0.5f), new(0.5f, 0.5f, 0.5f), new(0.5f, 0.5f, -0.5f), new(-0.5f, 0.5f, -0.5f));
        Face(new(0, -1, 0), new(1, 0, 0), new(-0.5f, -0.5f, -0.5f), new(0.5f, -0.5f, -0.5f), new(0.5f, -0.5f, 0.5f), new(-0.5f, -0.5f, 0.5f));
        Face(new(0, 0, 1), new(1, 0, 0), new(-0.5f, -0.5f, 0.5f), new(0.5f, -0.5f, 0.5f), new(0.5f, 0.5f, 0.5f), new(-0.5f, 0.5f, 0.5f));
        Face(new(0, 0, -1), new(-1, 0, 0), new(0.5f, -0.5f, -0.5f), new(-0.5f, -0.5f, -0.5f), new(-0.5f, 0.5f, -0.5f), new(0.5f, 0.5f, -0.5f));

        var idx = new ushort[36];
        for (ushort f = 0; f < 6; f++)
        {
            ushort b = (ushort)(f * 4);
            idx[f * 6 + 0] = b;
            idx[f * 6 + 1] = (ushort)(b + 1);
            idx[f * 6 + 2] = (ushort)(b + 2);
            idx[f * 6 + 3] = b;
            idx[f * 6 + 4] = (ushort)(b + 2);
            idx[f * 6 + 5] = (ushort)(b + 3);
        }
        return new MeshShape(v.ToArray(), idx);
    }

    /// <summary>1×1 quad in the XY plane (normal +Z) — same shape as the engine's default mesh (handle 0).</summary>
    public static MeshShape Quad() => MakeQuad(normal: new(0, 0, 1), tangent: new(1, 0, 0),
        new(-0.5f, -0.5f, 0), new(0.5f, -0.5f, 0), new(0.5f, 0.5f, 0), new(-0.5f, 0.5f, 0));

    /// <summary>1×1 horizontal plane (normal +Y) — a ground/floor primitive (scale to size).</summary>
    public static MeshShape Plane() => MakeQuad(normal: new(0, 1, 0), tangent: new(1, 0, 0),
        new(-0.5f, 0, 0.5f), new(0.5f, 0, 0.5f), new(0.5f, 0, -0.5f), new(-0.5f, 0, -0.5f));

    private static MeshShape MakeQuad(Vector3 normal, Vector3 tangent, Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3)
    {
        var v = new Vertex[4];
        v[0] = new Vertex { X = p0.X, Y = p0.Y, Z = p0.Z, Nx = normal.X, Ny = normal.Y, Nz = normal.Z, U = 0, V = 0, Tx = tangent.X, Ty = tangent.Y, Tz = tangent.Z, Tw = 1 };
        v[1] = new Vertex { X = p1.X, Y = p1.Y, Z = p1.Z, Nx = normal.X, Ny = normal.Y, Nz = normal.Z, U = 1, V = 0, Tx = tangent.X, Ty = tangent.Y, Tz = tangent.Z, Tw = 1 };
        v[2] = new Vertex { X = p2.X, Y = p2.Y, Z = p2.Z, Nx = normal.X, Ny = normal.Y, Nz = normal.Z, U = 1, V = 1, Tx = tangent.X, Ty = tangent.Y, Tz = tangent.Z, Tw = 1 };
        v[3] = new Vertex { X = p3.X, Y = p3.Y, Z = p3.Z, Nx = normal.X, Ny = normal.Y, Nz = normal.Z, U = 0, V = 1, Tx = tangent.X, Ty = tangent.Y, Tz = tangent.Z, Tw = 1 };
        return new MeshShape(v, new ushort[] { 0, 1, 2, 0, 2, 3 });
    }

    /// <summary>UV sphere of unit radius, centered at origin. <paramref name="segments"/> controls tessellation (longitude); rings = segments/2.</summary>
    public static MeshShape Sphere(int segments = 32)
    {
        if (segments < 3) segments = 3;
        int rings = Math.Max(2, segments / 2);
        var vlist = new List<Vertex>((rings + 1) * (segments + 1));

        for (int r = 0; r <= rings; r++)
        {
            float phi = MathF.PI * r / rings;          // 0..PI
            float y = MathF.Cos(phi);
            float sinPhi = MathF.Sin(phi);
            for (int s = 0; s <= segments; s++)
            {
                float theta = 2f * MathF.PI * s / segments; // 0..2PI
                float x = sinPhi * MathF.Cos(theta);
                float z = sinPhi * MathF.Sin(theta);
                var n = new Vector3(x, y, z); // already unit
                var t = new Vector3(-MathF.Sin(theta), 0, MathF.Cos(theta));
                vlist.Add(new Vertex
                {
                    X = x * 0.5f, Y = y * 0.5f, Z = z * 0.5f,
                    Nx = n.X, Ny = n.Y, Nz = n.Z,
                    U = (float)s / segments, V = (float)r / rings,
                    Tx = t.X, Ty = t.Y, Tz = t.Z, Tw = 1,
                });
            }
        }

        var ilist = new List<ushort>(rings * segments * 6);
        int row = segments + 1;
        for (int r = 0; r < rings; r++)
        {
            for (int s = 0; s < segments; s++)
            {
                ushort a = (ushort)(r * row + s);
                ushort b = (ushort)(a + row);
                ushort c = (ushort)(a + 1);
                ushort d = (ushort)(b + 1);
                ilist.Add(a); ilist.Add(b); ilist.Add(c);
                ilist.Add(c); ilist.Add(b); ilist.Add(d);
            }
        }
        return new MeshShape(vlist.ToArray(), ilist.ToArray());
    }
}
