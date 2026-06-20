using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_runtime_module_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public void* user_data;

    [NativeTypeName("bool (*)(ke_runtime *, void *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void*, ke_error**, bool> on_load;

    [NativeTypeName("void (*)(ke_runtime *, void *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void*, void> on_unload;
}
