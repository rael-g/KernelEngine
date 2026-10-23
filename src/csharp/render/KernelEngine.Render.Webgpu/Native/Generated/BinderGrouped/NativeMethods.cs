using System.Runtime.InteropServices;

using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_binder_grouped", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_resource_binder_grouped_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result render_resource_binder_grouped_create([NativeTypeName("const ke_render_resource_binder_grouped_params *")] ke_render_resource_binder_grouped_params* @params, [NativeTypeName("ke_render_resource_binder_handle *")] KernelEngine.Render.Native.ke_render_resource_binder_handle* out_binder);

    [DllImport("ke_render_binder_grouped", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_binder_grouped_set_log_callback", ExactSpelling = true)]
    public static extern void render_binder_grouped_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
