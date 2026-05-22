using System.Runtime.InteropServices;

namespace KernelEngine.Framework;

/// <summary>
/// ECS component holding spot light properties.
/// Position is read from the entity's <see cref="TransformComponent"/> world matrix at render time.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct SpotLightComponent
{
    /// <summary>Direction the cone points toward (world space, normalized).</summary>
    public float DirX, DirY, DirZ;

    /// <summary>Inner cone half-angle in radians (full intensity inside).</summary>
    public float InnerAngle;

    /// <summary>Outer cone half-angle in radians (zero intensity outside).</summary>
    public float OuterAngle;

    /// <summary>Attenuation range — intensity reaches zero at this distance.</summary>
    public float Range;

    /// <summary>Light color (linear).</summary>
    public float R, G, B;

    /// <summary>Multiplier applied to the color.</summary>
    public float Intensity;
}
