using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

/// <summary>Cone-shaped spot light for <c>ke_render::set_spot_lights</c>.</summary>
[StructLayout(LayoutKind.Sequential)]
public partial struct ke_spot_light
{
    /// <summary>World-space position.</summary>
    public float pos_x, pos_y, pos_z;

    /// <summary>Attenuation range — intensity reaches zero at this distance.</summary>
    public float range;

    /// <summary>Direction the cone points toward (world space, normalized).</summary>
    public float dir_x, dir_y, dir_z;

    /// <summary>Inner cone half-angle in radians (full intensity inside).</summary>
    public float inner_angle;

    /// <summary>Light color (linear).</summary>
    public float r, g, b;

    /// <summary>Multiplier applied to color.</summary>
    public float intensity;

    /// <summary>Outer cone half-angle in radians (zero intensity outside).</summary>
    public float outer_angle;
}
