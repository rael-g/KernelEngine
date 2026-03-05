using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

/// <summary>Descriptor passed to <c>ke_render::create_material</c>.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct ke_material_descriptor
{
    [NativeTypeName("float")] public float r;
    [NativeTypeName("float")] public float g;
    [NativeTypeName("float")] public float b;
    [NativeTypeName("float")] public float a;
    [NativeTypeName("ke_texture_handle")] public uint albedo;
    [NativeTypeName("float")] public float metallic;
    [NativeTypeName("float")] public float roughness;
}
