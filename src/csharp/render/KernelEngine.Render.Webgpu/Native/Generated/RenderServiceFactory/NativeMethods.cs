using System.Runtime.InteropServices;

using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_service", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_service_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result render_service_create([NativeTypeName("const ke_render_service_params *")] ke_render_service_params* @params, [NativeTypeName("ke_render_service_handle *")] KernelEngine.Render.Native.ke_render_service_handle* out_service);

    [DllImport("ke_render_service", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_service_set_log_callback", ExactSpelling = true)]
    public static extern void render_service_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
