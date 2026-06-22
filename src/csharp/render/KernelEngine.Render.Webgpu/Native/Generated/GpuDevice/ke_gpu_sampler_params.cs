using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_sampler_params
{
    public ke_gpu_filter min_filter;

    public ke_gpu_filter mag_filter;

    public ke_gpu_sampler_mipmap_filter mipmap_filter;

    public ke_gpu_address_mode address_mode_u;

    public ke_gpu_address_mode address_mode_v;

    public ke_gpu_address_mode address_mode_w;

    public float lod_min_clamp;

    public float lod_max_clamp;

    public ke_gpu_compare_function compare;

    [NativeTypeName("uint16_t")]
    public ushort max_anisotropy;
}
