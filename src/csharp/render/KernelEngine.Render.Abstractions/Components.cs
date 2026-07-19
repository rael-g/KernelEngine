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

// Light and environment vocabulary. These mirror the kernel's
// render/components.h one-for-one — field order is the ABI the render core
// reads, so it must not be reordered independently of that header.

/// <summary>Single directional light plus the ambient it seeds. First entity wins.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct DirectionalLightComponent
{
    /// <summary>The engine-wide component name this struct is registered under.</summary>
    public const string Name = "directional_light";

    public Vector3 Direction;
    public Vector3 Color;
    public float   Intensity;
    public Vector3 Ambient;
}

/// <summary>Point light parameters. Position comes from the entity's transform.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct PointLightComponent
{
    /// <summary>The engine-wide component name this struct is registered under.</summary>
    public const string Name = "point_light";

    public Vector3 Color;
    public float   Intensity;
    public float   Radius;
}

/// <summary>Spot light parameters. Position comes from the entity's transform.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct SpotLightComponent
{
    /// <summary>The engine-wide component name this struct is registered under.</summary>
    public const string Name = "spot_light";

    public Vector3 Direction;
    public Vector3 Color;
    public float   Intensity;
    public float   Range;
    public float   InnerAngleDeg;
    public float   OuterAngleDeg;
}

/// <summary>Scene-wide ambient light color. First entity wins.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct AmbientLightComponent
{
    /// <summary>The engine-wide component name this struct is registered under.</summary>
    public const string Name = "ambient_light";

    public Vector3 Color;
}

/// <summary>Environment cubemap driving both the skybox and image-based lighting.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct SkyboxComponent
{
    /// <summary>The engine-wide component name this struct is registered under.</summary>
    public const string Name = "skybox";

    public TextureHandle CubemapHandle;
}
