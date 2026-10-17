using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_command_buffer_handle
{
    public ke_gpu_command_buffer* @ref;

    [NativeTypeName("void (*)(ke_gpu_command_buffer *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_buffer*, void> destroy;
}
