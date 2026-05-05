using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

/// <summary>Material properties defining its appearance.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct ke_material
{
    [NativeTypeName("float")] public float r;
    [NativeTypeName("float")] public float g;
    [NativeTypeName("float")] public float b;
    [NativeTypeName("float")] public float a;
    public ke_texture_handle albedo;
    [NativeTypeName("float")] public float metallic;
    [NativeTypeName("float")] public float roughness;
    public ke_texture_handle normal_map;
}
