using System.Numerics;
using System.Runtime.InteropServices;

namespace KernelEngine.Ecs;

/// <summary>
/// ECS component holding the authored local pose, for a caller talking to the ECS
/// directly rather than through a node. Memory layout matches
/// <c>ke_transform_component</c> exactly. Carries only what a caller writes; where
/// the entity ended up in world space is <see cref="WorldTransformComponent"/>.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct TransformComponent
{
    public Vector3 Position;
    public Quaternion Rotation;
    public Vector3 Scale;

    /// <summary>The pose that applies no translation, rotation or scaling.</summary>
    public static TransformComponent Identity => new()
    {
        Position = Vector3.Zero,
        Rotation = Quaternion.Identity,
        Scale    = Vector3.One,
    };
}

/// <summary>
/// ECS component holding where an entity ended up in world space, composed down
/// the hierarchy. Memory layout matches <c>ke_world_transform_component</c> exactly.
/// The hierarchy is its only writer: a value written from game code is overwritten
/// on the next propagation.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct WorldTransformComponent
{
    /// <summary>The resolved world matrix.</summary>
    public Matrix4x4 Matrix;
}
