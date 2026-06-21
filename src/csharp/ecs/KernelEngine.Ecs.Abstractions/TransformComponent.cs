using System.Numerics;
using System.Runtime.InteropServices;

namespace KernelEngine.Ecs;

/// <summary>
/// ECS component that stores the local spatial transform and the computed world matrix.
/// Memory layout matches <c>ke_transform_component</c> exactly.
/// </summary>
/// <remarks>
/// Write <see cref="Position"/>, <see cref="Rotation"/>, and <see cref="Scale"/> each frame.
/// The <see cref="WorldMatrix"/> field is read-only output computed by the TransformSystem.
/// </remarks>
[StructLayout(LayoutKind.Sequential)]
public struct TransformComponent
{
    public Vector3 Position;
    public Quaternion Rotation;
    public Vector3 Scale;
    /// <summary>Computed by the TransformSystem — do not write directly.</summary>
    public Matrix4x4 WorldMatrix;

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
