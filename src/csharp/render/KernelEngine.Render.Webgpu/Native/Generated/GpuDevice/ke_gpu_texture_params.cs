using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_texture_params
{
    [NativeTypeName("uint32_t")]
    public uint width;

    [NativeTypeName("uint32_t")]
    public uint height;

    [NativeTypeName("uint32_t")]
    public uint depth_or_array_layers;

    public ke_gpu_texture_format format;

    public ke_gpu_texture_dimension dimension;

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
