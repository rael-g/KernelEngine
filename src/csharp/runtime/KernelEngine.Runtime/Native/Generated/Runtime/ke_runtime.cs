using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Runtime;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_runtime
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_runtime *, const ke_runtime_module_params *, ke_module_id *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ke_runtime_module_params*, ulong*, KernelEngine.Result.Native.Result> register_module;

    [NativeTypeName("ke_result (*)(ke_runtime *, const ke_runtime_system_params *, ke_system_id *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ke_runtime_system_params*, ulong*, KernelEngine.Result.Native.Result> register_system;

    [NativeTypeName("ke_result (*)(ke_runtime *, ke_system_id)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ulong, KernelEngine.Result.Native.Result> unregister_system;

    [NativeTypeName("ke_system_id (*)(ke_runtime *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, ulong> last_system;

    [NativeTypeName("ke_result (*)(ke_runtime *, ke_component_id, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.ComponentId, KernelEngine.Result.Native.Result> declare_exclusive;

    [NativeTypeName("ke_result (*)(ke_runtime *, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, global::KernelEngine.Ecs.ComponentId, KernelEngine.Result.Native.Result> declare_self_ordered;

    [NativeTypeName("ke_result (*)(ke_runtime *, bool)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, bool, KernelEngine.Result.Native.Result> check_order;

    [NativeTypeName("ke_result (*)(ke_runtime *, float)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, float, KernelEngine.Result.Native.Result> tick;

    [NativeTypeName("ke_result (*)(ke_runtime *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, KernelEngine.Result.Native.Result> flush_render;
}
