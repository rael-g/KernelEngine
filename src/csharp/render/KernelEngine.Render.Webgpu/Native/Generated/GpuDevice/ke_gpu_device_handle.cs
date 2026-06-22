using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_device_handle
{
    public ke_gpu_device* @ref;

    [NativeTypeName("void (*)(ke_gpu_device *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, void> destroy;
}
