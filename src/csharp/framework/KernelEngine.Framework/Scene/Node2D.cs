using System.Numerics;
using KernelEngine.Ecs;

namespace KernelEngine.Framework;

/// <summary>
/// 2D-facing facade over <see cref="Node3D"/>'s transform: <see cref="Position"/> and
/// <see cref="Scale"/> are <see cref="Vector2"/>, <see cref="Rotation"/> is a single
/// angle (radians, around Z). Backed by the same <c>ke_transform_component</c> as
/// every other node — Z stays at <see cref="Depth"/> (default 0) and rotation is a
/// Z-axis quaternion, so 2D and 3D nodes freely mix in one scene.
/// </summary>
public class Node2D : Node3D
{
    /// <summary>World-space depth (Z). Only relevant for 2D/3D draw-order mixing; defaults to 0.</summary>
    public float Depth
    {
        get => LocalTransform.Position.Z;
        set { var t = LocalTransform; t.Position.Z = value; LocalTransform = t; }
    }

    public Vector2 Position
    {
        get { var p = LocalTransform.Position; return new(p.X, p.Y); }
        set { var t = LocalTransform; t.Position.X = value.X; t.Position.Y = value.Y; LocalTransform = t; }
    }

    /// <summary>Rotation angle in radians around Z.</summary>
    public float Rotation
    {
        get => 2f * MathF.Atan2(LocalTransform.Rotation.Z, LocalTransform.Rotation.W);
        set { var t = LocalTransform; t.Rotation = Quaternion.CreateFromAxisAngle(Vector3.UnitZ, value); LocalTransform = t; }
    }

    public Vector2 Scale
    {
        get { var s = LocalTransform.Scale; return new(s.X, s.Y); }
        set { var t = LocalTransform; t.Scale.X = value.X; t.Scale.Y = value.Y; LocalTransform = t; }
    }
}
