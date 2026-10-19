using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_gpu_depth_stencil_attachment
{
    [NativeTypeName("ke_gpu_texture_view")]
    public ulong view;

    public ke_gpu_load_op depth_load_op;

    public ke_gpu_store_op depth_store_op;

    public ke_gpu_store_op stencil_store_op;

    public float clear_depth;

    [NativeTypeName("uint8_t")]
    public byte clear_stencil;

    public bool depth_read_only;

    public bool stencil_read_only;
}
