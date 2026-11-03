using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Io.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_binder_grouped", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_resource_binder_grouped_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_resource_binder_grouped_create([NativeTypeName("const ke_render_resource_binder_grouped_params *")] ke_render_resource_binder_grouped_params* @params, [NativeTypeName("ke_render_resource_binder_handle *")] KernelEngine.Render.Native.ke_render_resource_binder_handle* out_binder);

    [DllImport("ke_render_binder_grouped", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_binder_grouped_set_log_callback", ExactSpelling = true)]
    public static extern void render_binder_grouped_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
