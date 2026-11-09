using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct RenderPassIo
{
    [NativeTypeName("const char *")]
    public sbyte* Name;

    [NativeTypeName("const ke_component_id *")]
    public global::KernelEngine.Ecs.ComponentId* Reads;

    [NativeTypeName("uint32_t")]
    public uint ReadsCount;

    [NativeTypeName("const ke_component_id *")]
    public global::KernelEngine.Ecs.ComponentId* Writes;

    [NativeTypeName("uint32_t")]
    public uint WritesCount;

    [NativeTypeName("ke_render_chain_link")]
    public uint Chain;

    [NativeTypeName("ke_render_depth_mode")]
    public global::KernelEngine.Render.RenderDepthMode Depth;
}
