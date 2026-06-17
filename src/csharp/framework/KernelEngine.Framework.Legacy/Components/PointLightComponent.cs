using System.Runtime.InteropServices;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// ECS component holding point light properties.
/// Position is read from the entity's <see cref="TransformComponent"/> world matrix at render time.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct PointLightComponent
{
    /// <summary>Influence radius — attenuation reaches zero at this distance.</summary>
    public float Radius;

    /// <summary>Light color (linear).</summary>
    public float R, G, B;

    /// <summary>Multiplier applied to the color.</summary>
    public float Intensity;
}
