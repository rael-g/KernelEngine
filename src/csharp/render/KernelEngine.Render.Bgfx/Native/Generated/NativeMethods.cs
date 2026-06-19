using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Bgfx.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create", ExactSpelling = true)]
    public static extern ke_result render_bgfx_create([NativeTypeName("const ke_render_bgfx_params *")] ke_render_bgfx_params* @params, [NativeTypeName("ke_render_handle *")] KernelEngine.Render.Native.ke_render_handle* out_render, ke_error** out_error);
}
