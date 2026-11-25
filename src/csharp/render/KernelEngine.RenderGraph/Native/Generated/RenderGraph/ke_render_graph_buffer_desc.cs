using System.Numerics;

using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

using KernelEngine.Completion.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.RenderGraph.Native;

public unsafe partial struct ke_render_graph_buffer_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("uint64_t")]
    public ulong size;
}
