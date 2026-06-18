using KernelEngine.Kernel.Native;

namespace KernelEngine.Render.Bgfx.Native;

public unsafe partial struct ke_shader_compiler_bgfx_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Kernel.Native.ke_logger* logger;

    [NativeTypeName("const char *")]
    public sbyte* shaderc_path;
}
