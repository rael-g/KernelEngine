using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_forward", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_forward_create", ExactSpelling = true)]
    public static extern ke_render_forward_handle render_forward_create([NativeTypeName("const ke_render_forward_params *")] ke_render_forward_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
