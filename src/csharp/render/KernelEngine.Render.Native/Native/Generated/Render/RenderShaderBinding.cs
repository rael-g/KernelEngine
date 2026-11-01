using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct RenderShaderBinding
{
    [NativeTypeName("const char *")]
    public sbyte* Name;

    [NativeTypeName("ke_gpu_buffer")]
    public ulong Buffer;

    [NativeTypeName("uint64_t")]
    public ulong BufferOffset;

    [NativeTypeName("uint64_t")]
    public ulong BufferSize;

    [NativeTypeName("ke_gpu_texture_view")]
    public ulong TextureView;

    [NativeTypeName("ke_gpu_sampler")]
    public ulong Sampler;
}
