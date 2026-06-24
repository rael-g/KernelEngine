using System.Numerics;
using KernelEngine.Render;

namespace KernelEngine.Framework;

// Framework component vocabulary — POD structs stored in the ECS. Node
// subclasses write into these during OnBind; contributors read them each frame.

/// <summary>Renderable mesh + material pair on an entity.</summary>
public struct MeshRendererComponent
{
    public MeshHandle     Mesh;
    public MaterialHandle Material;
}

// CameraComponent and MeshComponent are the render-layer vocabulary (mirroring
// the kernel's render/components.h) and live in KernelEngine.Render.Abstractions
// — both raw-ECS games and the framework consume them from there (imported via
// `using KernelEngine.Render`). The framework-only structs below have no kernel
// counterpart and stay here.

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
