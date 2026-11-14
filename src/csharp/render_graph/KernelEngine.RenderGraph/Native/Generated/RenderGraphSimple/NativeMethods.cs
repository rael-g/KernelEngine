using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;
using global::KernelEngine.RenderGraph;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.RenderGraph.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_graph_simple", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_graph_simple_set_log_callback", ExactSpelling = true)]
    public static extern void render_graph_simple_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_render_graph_simple", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_graph_simple_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_graph_simple_create([NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, ke_render_graph_handle* out_graph);
}
