using System.Runtime.InteropServices;

namespace KernelEngine.Framework;

/// <summary>
/// ECS component holding camera projection parameters.
/// Stored contiguously in native memory via <see cref="EcsRegistry"/>.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct CameraComponent
{
    /// <summary>Vertical field of view in degrees (ignored when orthographic).</summary>
    public float Fov;

    /// <summary>Near clip plane distance.</summary>
    public float Near;

    /// <summary>Far clip plane distance.</summary>
    public float Far;

    /// <summary>Non-zero for orthographic projection, zero for perspective.</summary>
    public byte Orthographic;
}
