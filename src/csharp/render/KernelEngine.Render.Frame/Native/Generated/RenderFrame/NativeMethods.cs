using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

using KernelEngine.Part.Native;
using KernelEngine.RenderGraph.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Frame.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_frame", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_frame_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* render_frame_parts([NativeTypeName("size_t *")] nuint* out_count);
}
