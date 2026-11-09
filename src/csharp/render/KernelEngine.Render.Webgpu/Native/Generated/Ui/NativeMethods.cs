using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;
using global::KernelEngine.Text;

using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_ui_create([NativeTypeName("const ke_render_context *")] RenderContext* context, ke_render_ui_handle* out_ui);

    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_set_log_callback", ExactSpelling = true)]
    public static extern void render_ui_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
