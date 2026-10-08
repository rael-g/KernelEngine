using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_compute_pass_params
{
    [NativeTypeName("const char *")]
    public sbyte* label;
}
