using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

// Components are POD structs stored in the ECS. Nodes are the game-facing
// classes that game code instantiates with object-initializer syntax — they
// write into these components when added to the Tree.

/// <summary>World-space transform for an entity. Consumed by render systems.</summary>
public struct TransformComponent
{
    public Vector3 Position;
    public Quaternion Rotation;
    public Vector3 Scale;

    public static TransformComponent Identity => new()
    {
        Position = Vector3.Zero,
        Rotation = Quaternion.Identity,
        Scale    = Vector3.One,
    };

    /// <summary>Computes the world matrix from position/rotation/scale.</summary>
    public Matrix4x4 ToMatrix() =>
        Matrix4x4.CreateScale(Scale)
      * Matrix4x4.CreateFromQuaternion(Rotation)
      * Matrix4x4.CreateTranslation(Position);
}

/// <summary>Renderable mesh + material pair on an entity.</summary>
public struct MeshRendererComponent
{
    public MeshHandle     Mesh;
    public MaterialHandle Material;
}

/// <summary>Camera component. First entity with this drives the per-frame view/proj.</summary>
public struct CameraComponent
{
    public float FovDeg;
    public float Near;
    public float Far;
}

/// <summary>Single directional light + ambient. First entity wins (single-light pass).</summary>
public struct DirectionalLightComponent
{
    public Vector3 Direction;
    public Vector3 Color;
    public float   Intensity;
    public Vector3 Ambient;
}
