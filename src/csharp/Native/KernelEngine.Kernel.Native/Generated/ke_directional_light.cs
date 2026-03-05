using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

/// <summary>Directional light descriptor for <c>ke_render::set_directional_light</c>.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct ke_directional_light
{
    [NativeTypeName("float")] public float dir_x;
    [NativeTypeName("float")] public float dir_y;
    [NativeTypeName("float")] public float dir_z;
    [NativeTypeName("float")] public float r;
    [NativeTypeName("float")] public float g;
    [NativeTypeName("float")] public float b;
    [NativeTypeName("float")] public float intensity;
}
