using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_runtime_module_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public void* user_data;

    [NativeTypeName("ke_module_load_fn")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void*, KernelEngine.Common.Native.ke_error**, bool> on_load;

    [NativeTypeName("ke_module_unload_fn")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void*, void> on_unload;
}
