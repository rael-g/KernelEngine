using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_tonemap", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_tonemap_create", ExactSpelling = true)]
    public static extern ke_render_tonemap_handle render_tonemap_create([NativeTypeName("const ke_render_tonemap_params *")] ke_render_tonemap_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
