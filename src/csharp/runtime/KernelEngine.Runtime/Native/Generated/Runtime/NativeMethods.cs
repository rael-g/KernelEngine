using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Runtime.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_defer_applied_count", ExactSpelling = true)]
    [return: NativeTypeName("uint32_t")]
    public static extern uint system_ctx_defer_applied_count();

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_reset_defer_applied", ExactSpelling = true)]
    public static extern void system_ctx_reset_defer_applied();

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runtime_debug_compute_waves", ExactSpelling = true)]
    public static extern void runtime_debug_compute_waves([NativeTypeName("const ke_runtime_system_params *")] ke_runtime_system_params* systems, [NativeTypeName("uint32_t")] uint system_count, [NativeTypeName("uint32_t *")] uint* out_wave_assignments, [NativeTypeName("uint32_t *")] uint* out_wave_count);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_view", ExactSpelling = true)]
    [return: NativeTypeName("const ke_ecs_segment *")]
    public static extern KernelEngine.Ecs.Native.ke_ecs_segment* system_ctx_view(ke_system_ctx* ctx, [NativeTypeName("uint32_t")] uint query_index, [NativeTypeName("size_t *")] nuint* out_count);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_reserve", ExactSpelling = true)]
    [return: NativeTypeName("ke_entity")]
    public static extern ulong system_ctx_reserve(ke_system_ctx* ctx);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_defer", ExactSpelling = true)]
    public static extern bool system_ctx_defer(ke_system_ctx* ctx, [NativeTypeName("ke_defer_fn")] delegate* unmanaged[Cdecl]<KernelEngine.Ecs.Native.ke_ecs*, void*, void> fn, [NativeTypeName("const void *")] void* user, [NativeTypeName("size_t")] nuint user_size);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_spawn", ExactSpelling = true)]
    [return: NativeTypeName("ke_entity")]
    public static extern ulong system_ctx_spawn(ke_system_ctx* ctx);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_attach", ExactSpelling = true)]
    public static extern bool system_ctx_attach(ke_system_ctx* ctx, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint cid, [NativeTypeName("const void *")] void* data, [NativeTypeName("size_t")] nuint size);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_detach", ExactSpelling = true)]
    public static extern bool system_ctx_detach(ke_system_ctx* ctx, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint cid);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_despawn", ExactSpelling = true)]
    public static extern bool system_ctx_despawn(ke_system_ctx* ctx, [NativeTypeName("ke_entity")] ulong entity);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runtime_create", ExactSpelling = true)]
    public static extern ke_runtime_handle runtime_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_scheduler *")] KernelEngine.Scheduler.Native.ke_scheduler* scheduler, [NativeTypeName("const ke_runtime_params *")] ke_runtime_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
