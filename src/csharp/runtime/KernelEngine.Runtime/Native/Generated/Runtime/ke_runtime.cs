using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_runtime
{
    public void* handle;

    [NativeTypeName("ke_module_id (*)(ke_runtime *, const ke_runtime_module_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ke_runtime_module_params*, ke_error**, ulong> register_module;

    [NativeTypeName("ke_system_id (*)(ke_runtime *, const ke_runtime_system_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ke_runtime_system_params*, ke_error**, ulong> register_system;

    [NativeTypeName("bool (*)(ke_runtime *, float, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, float, ke_error**, bool> tick;

    [NativeTypeName("void (*)(ke_runtime *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void> flush_render;
}
