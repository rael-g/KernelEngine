using KernelEngine.Framework.Legacy.Native;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// A CPU-side mesh descriptor (vertices + indices) ready to be uploaded by
/// <see cref="ResourceManager.CreateMeshAsync(MeshShape)"/>. Static factories invoke the native
/// <c>ke_mesh_shape_bake</c> primitive — the actual vertex math lives in the ke_framework plugin.
/// </summary>
public sealed unsafe record MeshShape(Vertex[] Vertices, ushort[] Indices)
{
    /// <summary>1×1 quad in the XY plane (normal +Z) — same shape as the engine's default mesh (handle 0).</summary>
    public static MeshShape Quad() => BakeNative(ke_mesh_primitive.KE_MESH_PRIMITIVE_QUAD, segments: 0);

    /// <summary>1×1 horizontal plane (normal +Y) — a ground/floor primitive (scale to size).</summary>
    public static MeshShape Plane() => BakeNative(ke_mesh_primitive.KE_MESH_PRIMITIVE_PLANE, segments: 0);

    /// <summary>Unit cube centered at the origin, 24 vertices (4 per face) for per-face normals/UVs.</summary>
    public static MeshShape Cube() => BakeNative(ke_mesh_primitive.KE_MESH_PRIMITIVE_CUBE, segments: 0);

    /// <summary>UV sphere of unit diameter. <paramref name="segments"/> controls tessellation (longitude).</summary>
    public static MeshShape Sphere(int segments = 32) =>
        BakeNative(ke_mesh_primitive.KE_MESH_PRIMITIVE_SPHERE, segments: (uint)Math.Max(0, segments));

    private static MeshShape BakeNative(ke_mesh_primitive prim, uint segments)
    {
        using var allocator = new MallocAllocator();
        ke_mesh_shape_data data;
        KernelException.ThrowIfFailed(
            KernelEngine.Framework.Legacy.Native.NativeMethods.mesh_shape_bake(
                allocator.Native, prim, segments, &data).ToManaged());

        try
        {
            // ke_vertex (Kernel.Native) and Vertex (Kernel managed wrapper) share the same
            // memory layout — both are POD floats; copy field-by-field across the type identities.
            var verts = new Vertex[data.vertex_count];
            for (uint i = 0; i < data.vertex_count; i++)
            {
                var src = data.vertices[i];
                verts[i] = new Vertex
                {
                    X = src.x, Y = src.y, Z = src.z,
                    Nx = src.nx, Ny = src.ny, Nz = src.nz,
                    U = src.u, V = src.v,
                    Tx = src.tx, Ty = src.ty, Tz = src.tz, Tw = src.tw,
                };
            }
            var idx = new ushort[data.index_count];
            for (uint i = 0; i < data.index_count; i++) idx[i] = data.indices[i];
            return new MeshShape(verts, idx);
        }
        finally
        {
            KernelEngine.Framework.Legacy.Native.NativeMethods.mesh_shape_free(allocator.Native, &data);
        }
    }
}
