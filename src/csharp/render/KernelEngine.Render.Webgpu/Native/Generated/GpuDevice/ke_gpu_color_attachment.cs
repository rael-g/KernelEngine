using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_color_attachment
{
    [NativeTypeName("ke_gpu_texture_view")]
    public ulong view;

    public ke_gpu_load_op load_op;

    public ke_gpu_store_op store_op;

    public ke_gpu_clear_value clear_value;
}
