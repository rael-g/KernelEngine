using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_render_pass_params
{
    [NativeTypeName("const ke_gpu_color_attachment *")]
    public ke_gpu_color_attachment* color_attachments;

    [NativeTypeName("uint32_t")]
    public uint color_attachment_count;

    [NativeTypeName("const ke_gpu_depth_stencil_attachment *")]
    public ke_gpu_depth_stencil_attachment* depth_stencil_attachment;
}
