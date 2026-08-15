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

    public Vector4 BaseColor;
    public float   Roughness;
    public uint    AlphaMode;
    public float   AlphaCutoff;
    public float   Ior;
    public float   DistortionStrength;

    /// <summary>
    /// The defaults <c>ke_mesh_component</c> documents per field. A
    /// zero-initialized instance is not neutral — it is a black, fully rough,
    /// fully cut-out surface, which is valid memory that renders as nothing.
    /// </summary>
    public static MeshComponent Default => new()
    {
        BaseColor          = Vector4.One,
        Roughness          = 1.0f,
        AlphaMode          = 0,
        AlphaCutoff        = 0.5f,
        Ior                = 1.5f,
        DistortionStrength = 0.05f,
    };
}

/// <summary>
/// Scene-wide ambient light color. First entity wins. Kept as a managed mirror
/// (unlike Camera/DirectionalLight/PointLight/SpotLight, which kabic generates
/// straight onto <c>ke_ambient_light_component</c>) because the scene loader's
/// <c>[entity.components.AmbientLight]</c> property-apply path needs an
/// unmanaged struct type to key <see cref="IComponentRegistry.CidOf{T}"/> on;
/// ambient light has no native apply function (components_apply.zig), so this
/// is the only producer that still needs it.
/// </summary>
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
