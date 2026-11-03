using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_command_buffer_handle
{
    [NativeTypeName("ke_gpu_command_buffer *")]
    public GpuCommandBuffer* @ref;

    [NativeTypeName("void (*)(ke_gpu_command_buffer *)")]
    public delegate* unmanaged[Cdecl]<GpuCommandBuffer*, void> destroy;
}
