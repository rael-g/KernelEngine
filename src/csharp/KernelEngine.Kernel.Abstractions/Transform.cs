using System.Numerics;

namespace KernelEngine.Kernel;

/// <summary>
/// Spatial transform: position, rotation (quaternion), and scale.
/// </summary>
/// <remarks>
/// Layout is intentionally identical to the native <c>ke_transform</c> struct
/// so the concrete Kernel implementations can re-interpret it via <c>Unsafe.As</c>.
/// </remarks>
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
}
