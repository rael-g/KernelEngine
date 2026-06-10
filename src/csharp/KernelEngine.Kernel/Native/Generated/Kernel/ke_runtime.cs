namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_runtime
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_runtime *, const ke_runtime_module_params *, ke_module_id *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ke_runtime_module_params*, ulong*, ke_result> register_module;

    [NativeTypeName("ke_result (*)(ke_runtime *, const ke_runtime_system_params *, ke_system_id *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ke_runtime_system_params*, ulong*, ke_result> register_system;

    [NativeTypeName("ke_result (*)(ke_runtime *, float)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, float, ke_result> tick;

    [NativeTypeName("void (*)(ke_runtime *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void> destroy;
}
