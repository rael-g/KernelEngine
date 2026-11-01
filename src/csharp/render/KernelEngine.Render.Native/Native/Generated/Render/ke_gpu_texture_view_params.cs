using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_texture_view_params
{
    [NativeTypeName("const char *")]
    public sbyte* label;

    [NativeTypeName("ke_gpu_texture_format")]
    public global::KernelEngine.Render.GpuTextureFormat format;

    [NativeTypeName("ke_gpu_texture_dimension")]
    public global::KernelEngine.Render.GpuTextureDimension dimension;

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
