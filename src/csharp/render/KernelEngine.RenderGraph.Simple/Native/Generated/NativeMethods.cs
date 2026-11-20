using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;
using global::KernelEngine.RenderGraph;

using KernelEngine.Part.Native;
using KernelEngine.Render.Native;
using KernelEngine.RenderGraph.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.RenderGraph.Simple.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_graph_simple", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_graph_simple_set_log_callback", ExactSpelling = true)]
    public static extern void render_graph_simple_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_render_graph_simple", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_graph_simple_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_graph_simple_create([NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, [NativeTypeName("ke_render_graph_handle *")] KernelEngine.RenderGraph.Native.ke_render_graph_handle* out_graph);

    [DllImport("ke_render_graph_simple", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_graph_simple_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* render_graph_simple_parts([NativeTypeName("size_t *")] nuint* out_count);
}
