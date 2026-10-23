using System.Runtime.InteropServices;

using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result render_ui_create([NativeTypeName("const ke_render_ui_params *")] ke_render_ui_params* @params, ke_render_ui_handle* out_ui);

    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_set_log_callback", ExactSpelling = true)]
    public static extern void render_ui_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
