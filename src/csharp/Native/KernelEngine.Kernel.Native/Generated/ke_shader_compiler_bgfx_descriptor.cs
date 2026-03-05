namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_shader_compiler_bgfx_descriptor
{
    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_logger *")]
    public ke_logger* logger;

    [NativeTypeName("const char *")]
    public sbyte* shaderc_path;
}
