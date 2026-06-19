using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

// Framework component vocabulary — POD structs stored in the ECS. Node
// subclasses write into these during OnBind; contributors read them each frame.

/// <summary>Renderable mesh + material pair on an entity.</summary>
public struct MeshRendererComponent
{
    public MeshHandle     Mesh;
    public MaterialHandle Material;
}

/// <summary>
/// Camera component. First entity with this drives the per-frame view/proj.
/// Memory layout matches <c>ke_camera_component</c> exactly so the native
/// scene-loader apply callback and the managed contributor share one ECS slot.
/// </summary>
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct CameraComponent
{
    public float Fov;
    public float NearPlane;
    public float FarPlane;
    /// <summary>Half the vertical extent in world units (ortho only).</summary>
    public float OrthographicSize;
    /// <summary>Non-zero = orthographic projection; zero = perspective.</summary>
    public byte  Orthographic;
}

/// <summary>Single directional light + ambient. First entity wins (single-light pass).</summary>
public struct DirectionalLightComponent
{
    public Vector3 Direction;
    public Vector3 Color;
    public float   Intensity;
    public Vector3 Ambient;
}

/// <summary>Skybox cubemap. First entity with this drives the scene's skybox.</summary>
public struct SkyboxComponent
{
    public TextureHandle CubemapHandle;
}

/// <summary>Point light parameters. Position comes from the entity's transform.</summary>
public struct PointLightComponent
{
    public Vector3 Color;
    public float   Intensity;
    public float   Radius;
}

/// <summary>Scene-wide ambient light color. First entity wins.</summary>
public struct AmbientLightComponent
{
    public Vector3 Color;
}

/// <summary>Spot light parameters. Position comes from the entity's transform.</summary>
public struct SpotLightComponent
{
    public Vector3 Direction;
    public Vector3 Color;
    public float   Intensity;
    public float   Range;
    public float   InnerAngleDeg;
    public float   OuterAngleDeg;
}
