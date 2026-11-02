using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.View.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_shadow", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_shadow_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_shadow_create([NativeTypeName("const ke_render_shadow_params *")] ke_render_shadow_params* @params, ke_render_shadow_handle* out_shadow);

    [DllImport("ke_render_shadow", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_shadow_set_log_callback", ExactSpelling = true)]
    public static extern void render_shadow_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
