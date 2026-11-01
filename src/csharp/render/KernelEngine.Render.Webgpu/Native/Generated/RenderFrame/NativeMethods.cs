using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_frame", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_frame_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_frame_create([NativeTypeName("const ke_render_frame_params *")] ke_render_frame_params* @params, [NativeTypeName("ke_render_frame_handle *")] KernelEngine.Render.Native.ke_render_frame_handle* out_frame);

    [DllImport("ke_render_frame", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_frame_set_log_callback", ExactSpelling = true)]
    public static extern void render_frame_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
