using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_command_encoder_params
{
    [NativeTypeName("const char *")]
    public sbyte* label;
}
