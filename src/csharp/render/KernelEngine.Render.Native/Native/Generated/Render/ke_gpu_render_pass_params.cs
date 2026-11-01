using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_render_pass_params
{
    [NativeTypeName("const char *")]
    public sbyte* label;

    [NativeTypeName("const ke_gpu_color_attachment *")]
    public GpuColorAttachment* color_attachments;

    [NativeTypeName("uint32_t")]
    public uint color_attachment_count;

    [NativeTypeName("const ke_gpu_depth_stencil_attachment *")]
    public global::KernelEngine.Render.GpuDepthStencilAttachment* depth_stencil_attachment;
}
