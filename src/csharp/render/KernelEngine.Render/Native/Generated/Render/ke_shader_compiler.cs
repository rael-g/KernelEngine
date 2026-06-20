using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_shader_compiler
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_shader_compiler *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_shader_compiler*, ke_error**, bool> on_initialize;

    [NativeTypeName("bool (*)(struct ke_shader_compiler *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_shader_compiler*, ke_error**, bool> on_shutdown;

    [NativeTypeName("bool (*)(struct ke_shader_compiler *, const char *, const char *, const char *, const char *, const char *, const char **, size_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_shader_compiler*, sbyte*, sbyte*, sbyte*, sbyte*, sbyte*, sbyte**, nuint, ke_error**, bool> compile_shader;
}
