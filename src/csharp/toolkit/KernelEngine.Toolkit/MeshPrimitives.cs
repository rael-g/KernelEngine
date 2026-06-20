using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Static factories for procedural meshes. Each call materializes vertex + index
/// buffers on the GPU through the renderer. Call from a scene-setup callback
/// (render worker) for correct thread affinity.
/// </summary>
public static class MeshPrimitives
{
    /// <summary>Unit XZ plane centered at the origin, facing +Y.</summary>
    public static MeshHandle Plane(IRenderer renderer)
    {
        var verts = new Vertex[]
        {
            new() { X = -0.5f, Y = 0f, Z = -0.5f, Nx = 0, Ny = 1, Nz = 0, U = 0, V = 0, Tx = 1, Ty = 0, Tz = 0, Tw = 1 },
            new() { X =  0.5f, Y = 0f, Z = -0.5f, Nx = 0, Ny = 1, Nz = 0, U = 1, V = 0, Tx = 1, Ty = 0, Tz = 0, Tw = 1 },
            new() { X =  0.5f, Y = 0f, Z =  0.5f, Nx = 0, Ny = 1, Nz = 0, U = 1, V = 1, Tx = 1, Ty = 0, Tz = 0, Tw = 1 },
            new() { X = -0.5f, Y = 0f, Z =  0.5f, Nx = 0, Ny = 1, Nz = 0, U = 0, V = 1, Tx = 1, Ty = 0, Tz = 0, Tw = 1 },
        };
        var indices = new ushort[] { 0, 1, 2, 0, 2, 3 };
        return renderer.CreateMesh(verts, indices);
    }

    /// <summary>Unit XY quad centered at the origin, facing +Z.</summary>
    public static MeshHandle Quad(IRenderer renderer)
    {
        var verts = new Vertex[]
        {
            new() { X = -0.5f, Y = -0.5f, Z = 0f, Nx = 0, Ny = 0, Nz = 1, U = 0, V = 1, Tx = 1, Ty = 0, Tz = 0, Tw = 1 },
            new() { X =  0.5f, Y = -0.5f, Z = 0f, Nx = 0, Ny = 0, Nz = 1, U = 1, V = 1, Tx = 1, Ty = 0, Tz = 0, Tw = 1 },
            new() { X =  0.5f, Y =  0.5f, Z = 0f, Nx = 0, Ny = 0, Nz = 1, U = 1, V = 0, Tx = 1, Ty = 0, Tz = 0, Tw = 1 },
            new() { X = -0.5f, Y =  0.5f, Z = 0f, Nx = 0, Ny = 0, Nz = 1, U = 0, V = 0, Tx = 1, Ty = 0, Tz = 0, Tw = 1 },
        };
        var indices = new ushort[] { 0, 1, 2, 0, 2, 3 };
        return renderer.CreateMesh(verts, indices);
    }

    /// <summary>Unit cube centered at the origin, 24 verts (4 per face).</summary>
    public static MeshHandle Cube(IRenderer renderer)
    {
        const float h = 0.5f;
        var verts = new Vertex[24];
        var idx   = new ushort[36];

        void Face(int faceIdx, float nx, float ny, float nz, float tx, float ty, float tz,
                  System.Numerics.Vector3 p0, System.Numerics.Vector3 p1,
                  System.Numerics.Vector3 p2, System.Numerics.Vector3 p3)
        {
            int v = faceIdx * 4;
            verts[v + 0] = new Vertex { X = p0.X, Y = p0.Y, Z = p0.Z, Nx = nx, Ny = ny, Nz = nz, U = 0, V = 0, Tx = tx, Ty = ty, Tz = tz, Tw = 1 };
            verts[v + 1] = new Vertex { X = p1.X, Y = p1.Y, Z = p1.Z, Nx = nx, Ny = ny, Nz = nz, U = 1, V = 0, Tx = tx, Ty = ty, Tz = tz, Tw = 1 };
            verts[v + 2] = new Vertex { X = p2.X, Y = p2.Y, Z = p2.Z, Nx = nx, Ny = ny, Nz = nz, U = 1, V = 1, Tx = tx, Ty = ty, Tz = tz, Tw = 1 };
            verts[v + 3] = new Vertex { X = p3.X, Y = p3.Y, Z = p3.Z, Nx = nx, Ny = ny, Nz = nz, U = 0, V = 1, Tx = tx, Ty = ty, Tz = tz, Tw = 1 };

            int i = faceIdx * 6;
            idx[i + 0] = (ushort)(v + 0); idx[i + 1] = (ushort)(v + 1); idx[i + 2] = (ushort)(v + 2);
            idx[i + 3] = (ushort)(v + 0); idx[i + 4] = (ushort)(v + 2); idx[i + 5] = (ushort)(v + 3);
        }

        Face(0,  1, 0, 0,  0, 0,-1, new(+h,-h,+h), new(+h,-h,-h), new(+h,+h,-h), new(+h,+h,+h));
        Face(1, -1, 0, 0,  0, 0, 1, new(-h,-h,-h), new(-h,-h,+h), new(-h,+h,+h), new(-h,+h,-h));
        Face(2,  0, 1, 0,  1, 0, 0, new(-h,+h,+h), new(+h,+h,+h), new(+h,+h,-h), new(-h,+h,-h));
        Face(3,  0,-1, 0,  1, 0, 0, new(-h,-h,-h), new(+h,-h,-h), new(+h,-h,+h), new(-h,-h,+h));
        Face(4,  0, 0, 1,  1, 0, 0, new(-h,-h,+h), new(+h,-h,+h), new(+h,+h,+h), new(-h,+h,+h));
        Face(5,  0, 0,-1, -1, 0, 0, new(+h,-h,-h), new(-h,-h,-h), new(-h,+h,-h), new(+h,+h,-h));

        return renderer.CreateMesh(verts, idx);
    }
}
