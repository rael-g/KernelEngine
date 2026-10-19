using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_frame", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_frame_create", ExactSpelling = true)]
    public static extern ke_render_frame_handle render_frame_create([NativeTypeName("const ke_render_frame_params *")] ke_render_frame_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
