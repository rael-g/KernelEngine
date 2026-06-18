namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_shader_compiler_handle
{
    public ke_shader_compiler* @ref;

    [NativeTypeName("void (*)(ke_shader_compiler *)")]
    public delegate* unmanaged[Cdecl]<ke_shader_compiler*, void> destroy;
}
