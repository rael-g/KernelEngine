using System.Runtime.InteropServices;

using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.View.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_shadow", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_shadow_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result render_shadow_create([NativeTypeName("const ke_render_shadow_params *")] ke_render_shadow_params* @params, ke_render_shadow_handle* out_shadow);

    [DllImport("ke_render_shadow", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_shadow_set_log_callback", ExactSpelling = true)]
    public static extern void render_shadow_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
