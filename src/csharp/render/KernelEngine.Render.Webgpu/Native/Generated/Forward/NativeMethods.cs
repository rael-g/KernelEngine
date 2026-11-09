using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_forward", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_forward_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_forward_create([NativeTypeName("const ke_render_context *")] RenderContext* context, [NativeTypeName("const ke_render_forward_config *")] ke_render_forward_config* config, ke_render_forward_handle* out_forward);

    [DllImport("ke_render_forward", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_forward_set_log_callback", ExactSpelling = true)]
    public static extern void render_forward_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
