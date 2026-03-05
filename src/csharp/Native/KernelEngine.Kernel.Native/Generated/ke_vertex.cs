using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

/// <summary>Per-vertex data passed to <c>ke_render::create_mesh</c>.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct ke_vertex
{
    [NativeTypeName("float")] public float x;
    [NativeTypeName("float")] public float y;
    [NativeTypeName("float")] public float z;
    [NativeTypeName("float")] public float nx;
    [NativeTypeName("float")] public float ny;
    [NativeTypeName("float")] public float nz;
    [NativeTypeName("float")] public float u;
    [NativeTypeName("float")] public float v;
}
