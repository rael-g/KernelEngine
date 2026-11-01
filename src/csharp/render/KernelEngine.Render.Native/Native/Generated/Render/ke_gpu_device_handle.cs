using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_device_handle
{
    public ke_gpu_device* @ref;

    [NativeTypeName("void (*)(ke_gpu_device *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, void> destroy;
}
