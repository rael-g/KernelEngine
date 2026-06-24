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

/// <summary>
/// ECS camera component. Memory layout matches <c>ke_camera_component</c>; a
/// render system reads the first camera entity to build the view-projection.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct CameraComponent
{
    /// <summary>The engine-wide component name this struct is registered under.</summary>
    public const string Name = "camera";

    public float Fov;
    public float NearPlane;
    public float FarPlane;
    public float OrthographicSize;
    public byte  Orthographic;
}

// 32-byte inline storage mirroring ke_mesh_component's char primitive[32] tag.
[InlineArray(32)]
public struct PrimitiveTag
{
    private byte _element0;
}

/// <summary>
/// ECS mesh component. Memory layout matches <c>ke_mesh_component</c>; a render
/// system resolves <see cref="Mesh"/> to GPU buffers and <see cref="Material"/>
/// to its surface appearance (base color + albedo).
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct MeshComponent
{
    /// <summary>The engine-wide component name this struct is registered under.</summary>
    public const string Name = "mesh";

    public MeshHandle     Mesh;
    public MaterialHandle Material;
    public PrimitiveTag   Primitive;
}
