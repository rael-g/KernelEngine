using System.Runtime.InteropServices;
using KernelEngine.Ecs;

namespace KernelEngine.Framework.Legacy;

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

    /// <summary>
    /// Half-height of the orthographic viewport in world units (ignored when perspective).
    /// E.g. <c>5</c> = viewport is 10 units tall; horizontal extents derive from aspect ratio.
    /// </summary>
    public float OrthographicSize;

    /// <summary>Non-zero for orthographic projection, zero for perspective.</summary>
    public byte Orthographic;
}
