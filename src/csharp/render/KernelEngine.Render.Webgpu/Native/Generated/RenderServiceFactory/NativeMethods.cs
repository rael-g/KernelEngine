using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Io.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_service", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_service_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_service_create([NativeTypeName("const ke_render_service_params *")] ke_render_service_params* @params, [NativeTypeName("ke_render_service_handle *")] KernelEngine.Render.Native.ke_render_service_handle* out_service);

    [DllImport("ke_render_service", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_service_set_log_callback", ExactSpelling = true)]
    public static extern void render_service_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
