using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Bgfx.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result render_bgfx_create([NativeTypeName("const ke_render_bgfx_params *")] ke_render_bgfx_params* @params, [NativeTypeName("ke_render **")] KernelEngine.Kernel.Native.ke_render** out_render);
}
