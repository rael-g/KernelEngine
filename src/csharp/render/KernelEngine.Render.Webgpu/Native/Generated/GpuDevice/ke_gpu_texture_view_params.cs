using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_gpu_texture_view_params
{
    public ke_gpu_texture_format format;

    public ke_gpu_texture_dimension dimension;

    [NativeTypeName("ke_gpu_texture_aspect")]
    public uint aspect;

    [NativeTypeName("uint8_t")]
    public byte base_mip_level;

    [NativeTypeName("uint8_t")]
    public byte mip_level_count;

    [NativeTypeName("uint8_t")]
    public byte base_array_layer;

    [NativeTypeName("uint8_t")]
    public byte array_layer_count;
}
