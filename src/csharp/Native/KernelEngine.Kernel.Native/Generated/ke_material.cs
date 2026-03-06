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
    [NativeTypeName("ke_texture_handle")] public uint albedo;
    [NativeTypeName("float")] public float metallic;
    [NativeTypeName("float")] public float roughness;
    [NativeTypeName("ke_texture_handle")] public uint normal_map;
}
