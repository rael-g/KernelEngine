using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_command_encoder_handle
{
    public ke_gpu_command_encoder* @ref;

    [NativeTypeName("void (*)(ke_gpu_command_encoder *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_command_encoder*, void> destroy;
}
