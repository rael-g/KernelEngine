using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_service", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_service_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_render_service_handle")]
    public static extern KernelEngine.Render.Native.ke_render_service_handle render_service_create([NativeTypeName("const ke_render_service_params *")] ke_render_service_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_render_service", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_service_set_log_callback", ExactSpelling = true)]
    public static extern void render_service_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
