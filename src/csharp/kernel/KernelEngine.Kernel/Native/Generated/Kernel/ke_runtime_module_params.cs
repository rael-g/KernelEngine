namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_runtime_module_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public void* user_data;

    [NativeTypeName("ke_result (*)(ke_runtime *, void *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void*, ke_result> on_load;

    [NativeTypeName("void (*)(ke_runtime *, void *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void*, void> on_unload;
}
