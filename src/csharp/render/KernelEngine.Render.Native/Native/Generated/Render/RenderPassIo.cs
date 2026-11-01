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

    [NativeTypeName("const char *const *")]
    public sbyte** Reads;

    [NativeTypeName("uint32_t")]
    public uint ReadsCount;

    [NativeTypeName("const char *const *")]
    public sbyte** Writes;

    [NativeTypeName("uint32_t")]
    public uint WritesCount;

    [NativeTypeName("ke_render_chain_link")]
    public uint Chain;

    [NativeTypeName("ke_render_depth_mode")]
    public global::KernelEngine.Render.RenderDepthMode Depth;
}
