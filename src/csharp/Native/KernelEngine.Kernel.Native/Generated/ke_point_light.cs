using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

/// <summary>Omnidirectional point light for <c>ke_render::set_point_lights</c>.</summary>
[StructLayout(LayoutKind.Sequential)]
public partial struct ke_point_light
{
    /// <summary>World-space position.</summary>
    public float pos_x, pos_y, pos_z;

    /// <summary>Influence radius — attenuation reaches zero at this distance.</summary>
    public float radius;

    /// <summary>Light color (linear).</summary>
    public float r, g, b;

    /// <summary>Multiplier applied to color.</summary>
    public float intensity;
}
