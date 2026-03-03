using KernelEngine.Core.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Glfw.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_window_glfw", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_window_glfw_create", ExactSpelling = true)]
    public static extern ke_result window_glfw_create([NativeTypeName("const ke_window_glfw_descriptor *")] ke_window_glfw_descriptor* desc, ke_system** out_system);

    [DllImport("ke_window_glfw", CallingConvention = CallingConvention.Cdecl, EntryPoint = "?CreateGlfwWindowSystem@window@domain@kernel_engine@@YA?AW4ke_result@@PEBUke_window_glfw_descriptor@@PEAPEAUke_system@@@Z", ExactSpelling = true)]
    public static extern ke_result CreateGlfwWindowSystem([NativeTypeName("const ke_window_glfw_descriptor *")] ke_window_glfw_descriptor* desc, ke_system** out_system);
}
