using System.Runtime.InteropServices;

using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.View.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_camera", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_camera_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_render_camera_handle")]
    public static extern KernelEngine.Render.Native.ke_render_camera_handle render_camera_create([NativeTypeName("ke_view_space *")] KernelEngine.View.Native.ke_view_space* view_space, [NativeTypeName("const ke_ndc_convention *")] KernelEngine.Render.Native.ke_ndc_convention* clip, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_render_camera", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_camera_set_log_callback", ExactSpelling = true)]
    public static extern void render_camera_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
