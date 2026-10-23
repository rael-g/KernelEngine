using System.Runtime.InteropServices;

using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_frame", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_frame_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result render_frame_create([NativeTypeName("const ke_render_frame_params *")] ke_render_frame_params* @params, ke_render_frame_handle* out_frame);

    [DllImport("ke_render_frame", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_frame_set_log_callback", ExactSpelling = true)]
    public static extern void render_frame_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
