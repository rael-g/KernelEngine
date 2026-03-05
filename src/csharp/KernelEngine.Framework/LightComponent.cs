using System.Runtime.InteropServices;

namespace KernelEngine.Framework;

/// <summary>
/// ECS component holding directional light parameters.
/// Stored contiguously in native memory via <see cref="EcsRegistry"/>.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct LightComponent
{
    /// <summary>Direction toward the light source (world space, normalized).</summary>
    public float DirX, DirY, DirZ;

    /// <summary>Light color (linear).</summary>
    public float R, G, B;

    /// <summary>Multiplier applied to the color.</summary>
    public float Intensity;
}
