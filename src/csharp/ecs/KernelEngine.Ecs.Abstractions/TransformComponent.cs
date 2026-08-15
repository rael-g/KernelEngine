using System.Numerics;
using System.Runtime.InteropServices;

namespace KernelEngine.Ecs;

/// <summary>
/// ECS component holding the authored local pose. Memory layout matches
/// <c>ke_transform_component</c> exactly.
/// </summary>
/// <remarks>
/// Carries only what a caller writes. Where the entity ended up in world space is
/// <see cref="WorldTransformComponent"/>, written by the hierarchy alone.
/// </remarks>
[StructLayout(LayoutKind.Sequential)]
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

    public readonly Matrix4x4 ToMatrix() =>
        Matrix4x4.CreateScale(Scale)
      * Matrix4x4.CreateFromQuaternion(Rotation)
      * Matrix4x4.CreateTranslation(Position);
}

/// <summary>
/// ECS component holding where an entity ended up in world space, composed down
/// the hierarchy. Memory layout matches <c>ke_world_transform_component</c> exactly.
/// </summary>
/// <remarks>
/// Output of the hierarchy, which is its only writer: writing it from game code is
/// overwritten on the next propagation.
/// </remarks>
[StructLayout(LayoutKind.Sequential)]
public struct WorldTransformComponent
{
    /// <summary>The resolved world matrix.</summary>
    public Matrix4x4 Matrix;
}
