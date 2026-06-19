using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_runtime
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_runtime *, const ke_runtime_module_params *, ke_module_id *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ke_runtime_module_params*, ulong*, ke_error**, ke_result> register_module;

    [NativeTypeName("ke_result (*)(ke_runtime *, const ke_runtime_system_params *, ke_system_id *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ke_runtime_system_params*, ulong*, ke_error**, ke_result> register_system;

    [NativeTypeName("ke_result (*)(ke_runtime *, float, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, float, ke_error**, ke_result> tick;
}
