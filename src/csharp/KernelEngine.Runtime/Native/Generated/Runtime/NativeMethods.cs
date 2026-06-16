using System.Runtime.InteropServices;

namespace KernelEngine.Runtime.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runtime_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern int runtime_create(ke_ecs* ecs, ke_task_scheduler* task_scheduler, [NativeTypeName("const ke_runtime_params *")] ke_runtime_params* @params, ke_runtime** out_runtime);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_get_mut", ExactSpelling = true)]
    public static extern void* system_ctx_get_mut(ke_system_ctx* ctx, [NativeTypeName("ke_component_id")] uint cid, [NativeTypeName("ke_entity")] ulong entity);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_get", ExactSpelling = true)]
    [return: NativeTypeName("const void *")]
    public static extern void* system_ctx_get(ke_system_ctx* ctx, [NativeTypeName("ke_component_id")] uint cid, [NativeTypeName("ke_entity")] ulong entity);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_check_failures", ExactSpelling = true)]
    [return: NativeTypeName("uint32_t")]
    public static extern uint system_ctx_check_failures();

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_reset_check_failures", ExactSpelling = true)]
    public static extern void system_ctx_reset_check_failures();

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_defer_applied_count", ExactSpelling = true)]
    [return: NativeTypeName("uint32_t")]
    public static extern uint system_ctx_defer_applied_count();

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_reset_defer_applied", ExactSpelling = true)]
    public static extern void system_ctx_reset_defer_applied();

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_runtime_debug_compute_waves", ExactSpelling = true)]
    public static extern void runtime_debug_compute_waves([NativeTypeName("const ke_runtime_system_params *")] ke_runtime_system_params* systems, [NativeTypeName("uint32_t")] uint system_count, [NativeTypeName("uint32_t *")] uint* out_wave_assignments, [NativeTypeName("uint32_t *")] uint* out_wave_count);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_query", ExactSpelling = true)]
    public static extern void system_ctx_query(ke_system_ctx* ctx, [NativeTypeName("ke_component_id")] uint cid, [NativeTypeName("ke_entity **")] ulong** out_entities, void** out_data, [NativeTypeName("size_t *")] nuint* out_count);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_spawn", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern int system_ctx_spawn(ke_system_ctx* ctx, [NativeTypeName("ke_entity *")] ulong* out_entity);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_attach", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern int system_ctx_attach(ke_system_ctx* ctx, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint cid, [NativeTypeName("const void *")] void* data, [NativeTypeName("size_t")] nuint size);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_detach", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern int system_ctx_detach(ke_system_ctx* ctx, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint cid);

    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_system_ctx_despawn", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern int system_ctx_despawn(ke_system_ctx* ctx, [NativeTypeName("ke_entity")] ulong entity);
}
