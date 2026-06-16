namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_shader_compiler
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_shader_compiler *)")]
    public delegate* unmanaged[Cdecl]<ke_shader_compiler*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_shader_compiler *)")]
    public delegate* unmanaged[Cdecl]<ke_shader_compiler*, int> on_initialize;

    [NativeTypeName("ke_result (*)(struct ke_shader_compiler *)")]
    public delegate* unmanaged[Cdecl]<ke_shader_compiler*, int> on_shutdown;

    [NativeTypeName("ke_result (*)(struct ke_shader_compiler *, const char *, const char *, const char *, const char *, const char *, const char **, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_shader_compiler*, sbyte*, sbyte*, sbyte*, sbyte*, sbyte*, sbyte**, nuint, int> compile_shader;
}
