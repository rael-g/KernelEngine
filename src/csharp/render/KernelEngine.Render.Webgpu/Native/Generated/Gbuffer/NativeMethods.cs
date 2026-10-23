using System.Runtime.InteropServices;

using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_gbuffer", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_gbuffer_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result render_gbuffer_create([NativeTypeName("const ke_render_gbuffer_params *")] ke_render_gbuffer_params* @params, ke_render_gbuffer_handle* out_gbuffer);

    [DllImport("ke_render_gbuffer", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_gbuffer_set_log_callback", ExactSpelling = true)]
    public static extern void render_gbuffer_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
