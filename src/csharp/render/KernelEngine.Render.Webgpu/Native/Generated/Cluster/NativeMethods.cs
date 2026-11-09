using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_cluster", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_cluster_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_cluster_create([NativeTypeName("const ke_render_context *")] RenderContext* context, [NativeTypeName("const ke_render_cluster_config *")] ke_render_cluster_config* config, [NativeTypeName("ke_render_cluster_resources *")] global::KernelEngine.Render.RenderClusterResources* out_resources, ke_render_cluster_handle* out_cluster);

    [DllImport("ke_render_cluster", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_cluster_set_log_callback", ExactSpelling = true)]
    public static extern void render_cluster_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
