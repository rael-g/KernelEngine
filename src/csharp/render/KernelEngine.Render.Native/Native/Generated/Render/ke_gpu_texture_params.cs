using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_texture_params
{
    [NativeTypeName("const char *")]
    public sbyte* label;

    [NativeTypeName("uint32_t")]
    public uint width;

    [NativeTypeName("uint32_t")]
    public uint height;

    [NativeTypeName("uint32_t")]
    public uint depth_or_array_layers;

    [NativeTypeName("ke_gpu_texture_format")]
    public global::KernelEngine.Render.GpuTextureFormat format;

    [NativeTypeName("ke_gpu_texture_dimension")]
    public global::KernelEngine.Render.GpuTextureDimension dimension;

    [NativeTypeName("ke_gpu_texture_usage")]
    public uint usage;

    [NativeTypeName("uint8_t")]
    public byte mip_level_count;

    [NativeTypeName("uint8_t")]
    public byte sample_count;

    [NativeTypeName("const void *")]
    public void* initial_data;

    [NativeTypeName("uint32_t")]
    public uint initial_data_size;
}
