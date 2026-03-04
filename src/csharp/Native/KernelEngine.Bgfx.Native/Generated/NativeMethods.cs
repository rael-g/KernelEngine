using KernelEngine.Core.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Bgfx.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create", ExactSpelling = true)]
    public static extern ke_result render_bgfx_create([NativeTypeName("const ke_render_bgfx_descriptor *")] ke_render_bgfx_descriptor* desc, ke_system** out_system);
}
