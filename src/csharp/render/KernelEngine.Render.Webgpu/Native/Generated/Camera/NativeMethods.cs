using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_camera", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_camera_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_render_camera_handle")]
    public static extern KernelEngine.Render.Native.ke_render_camera_handle render_camera_create([NativeTypeName("ke_view_space *")] KernelEngine.View.Native.ke_view_space* view_space, [NativeTypeName("const ke_ndc_convention *")] KernelEngine.View.Native.ke_ndc_convention* clip, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
