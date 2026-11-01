using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.View.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_camera", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_camera_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_camera_create([NativeTypeName("ke_view_space *")] KernelEngine.View.Native.ke_view_space* view_space, [NativeTypeName("const ke_ndc_convention *")] global::KernelEngine.Render.NdcConvention* clip, [NativeTypeName("ke_render_camera_handle *")] KernelEngine.Render.Native.ke_render_camera_handle* out_camera);

    [DllImport("ke_render_camera", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_camera_set_log_callback", ExactSpelling = true)]
    public static extern void render_camera_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
