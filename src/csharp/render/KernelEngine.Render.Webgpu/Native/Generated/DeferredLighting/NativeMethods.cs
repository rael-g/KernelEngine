using System.Runtime.InteropServices;

using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_deferred_lighting", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_deferred_lighting_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result render_deferred_lighting_create([NativeTypeName("const ke_render_deferred_lighting_params *")] ke_render_deferred_lighting_params* @params, ke_render_deferred_lighting_handle* out_lighting);

    [DllImport("ke_render_deferred_lighting", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_deferred_lighting_set_log_callback", ExactSpelling = true)]
    public static extern void render_deferred_lighting_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
