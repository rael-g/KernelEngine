using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_gpu_shader_module_params
{
    [NativeTypeName("const uint32_t *")]
    public uint* code;

    [NativeTypeName("size_t")]
    public nuint byte_size;

    [NativeTypeName("const char *")]
    public sbyte* entry_point;
}
