using System.Numerics;
using System.Runtime.CompilerServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// Spatial transform: position, rotation (quaternion), and scale.
/// Memory layout is identical to <c>ke_transform</c> (ke_vec3, ke_quat, ke_vec3).
/// </summary>
public struct Transform
{
    public Vector3 Position;
    public Quaternion Rotation;
    public Vector3 Scale;

    public static readonly Transform Identity = new()
    {
        Position = Vector3.Zero,
        Rotation = Quaternion.Identity,
        Scale = Vector3.One,
    };

    internal static Transform FromNative(ke_transform t) =>
        Unsafe.As<ke_transform, Transform>(ref t);

    internal ke_transform ToNative() =>
        Unsafe.As<Transform, ke_transform>(ref this);
}
