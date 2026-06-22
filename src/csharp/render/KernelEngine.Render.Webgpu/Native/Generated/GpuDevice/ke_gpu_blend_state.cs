using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_blend_state
{
    [NativeTypeName("ke_bool")]
    public byte blend_enabled;

    public ke_gpu_blend_factor src_color;

    public ke_gpu_blend_factor dst_color;

    public ke_gpu_blend_op color_op;

    public ke_gpu_blend_factor src_alpha;

    public ke_gpu_blend_factor dst_alpha;

    public ke_gpu_blend_op alpha_op;

    [NativeTypeName("uint8_t")]
    public byte write_mask;
}
