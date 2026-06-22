using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_depth_stencil_state
{
    [NativeTypeName("ke_bool")]
    public byte depth_test_enabled;

    [NativeTypeName("ke_bool")]
    public byte depth_write_enabled;

    public ke_gpu_compare_function depth_compare;

    [NativeTypeName("ke_bool")]
    public byte stencil_test_enabled;

    public ke_gpu_stencil_op stencil_front_fail;

    public ke_gpu_stencil_op stencil_front_depth_fail;

    public ke_gpu_stencil_op stencil_front_pass;

    public ke_gpu_compare_function stencil_front_compare;

    public ke_gpu_stencil_op stencil_back_fail;

    public ke_gpu_stencil_op stencil_back_depth_fail;

    public ke_gpu_stencil_op stencil_back_pass;

    public ke_gpu_compare_function stencil_back_compare;

    [NativeTypeName("uint8_t")]
    public byte stencil_read_mask;

    [NativeTypeName("uint8_t")]
    public byte stencil_write_mask;
}
