using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_sampler_params
{
    [NativeTypeName("const char *")]
    public sbyte* label;

    [NativeTypeName("ke_gpu_filter")]
    public global::KernelEngine.Render.GpuFilter min_filter;

    [NativeTypeName("ke_gpu_filter")]
    public global::KernelEngine.Render.GpuFilter mag_filter;

    [NativeTypeName("ke_gpu_sampler_mipmap_filter")]
    public global::KernelEngine.Render.GpuSamplerMipmapFilter mipmap_filter;

    [NativeTypeName("ke_gpu_address_mode")]
    public global::KernelEngine.Render.GpuAddressMode address_mode_u;

    [NativeTypeName("ke_gpu_address_mode")]
    public global::KernelEngine.Render.GpuAddressMode address_mode_v;

    [NativeTypeName("ke_gpu_address_mode")]
    public global::KernelEngine.Render.GpuAddressMode address_mode_w;

    public float lod_min_clamp;

    public float lod_max_clamp;

    [NativeTypeName("ke_gpu_compare_function")]
    public global::KernelEngine.Render.GpuCompareFunction compare;

    [NativeTypeName("uint16_t")]
    public ushort max_anisotropy;
}
