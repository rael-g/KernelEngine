using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_runtime
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_runtime *, const ke_runtime_module_params *, ke_module_id *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ke_runtime_module_params*, ulong*, KernelEngine.Result.Native.ke_result> register_module;

    [NativeTypeName("ke_result (*)(ke_runtime *, const ke_runtime_system_params *, ke_system_id *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ke_runtime_system_params*, ulong*, KernelEngine.Result.Native.ke_result> register_system;

    [NativeTypeName("ke_result (*)(ke_runtime *, ke_system_id)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ulong, KernelEngine.Result.Native.ke_result> unregister_system;

    [NativeTypeName("ke_system_id (*)(ke_runtime *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ulong> last_system;

    [NativeTypeName("ke_result (*)(ke_runtime *, ke_component_id, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, uint, uint, KernelEngine.Result.Native.ke_result> declare_exclusive;

    [NativeTypeName("ke_result (*)(ke_runtime *, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, uint, KernelEngine.Result.Native.ke_result> declare_self_ordered;

    [NativeTypeName("ke_result (*)(ke_runtime *, bool)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, bool, KernelEngine.Result.Native.ke_result> check_order;

    [NativeTypeName("ke_result (*)(ke_runtime *, float)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, float, KernelEngine.Result.Native.ke_result> tick;

    [NativeTypeName("ke_result (*)(ke_runtime *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, KernelEngine.Result.Native.ke_result> flush_render;
}
