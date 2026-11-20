using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Extraction.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_extraction_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_extraction_default_set_log_callback", ExactSpelling = true)]
    public static extern void extraction_default_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_extraction_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_extraction_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result extraction_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* main, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* render, [NativeTypeName("ke_scheduler *")] KernelEngine.Scheduler.Native.ke_scheduler* scheduler, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* render_schedule, ke_extraction_handle* out_extraction);

    [DllImport("ke_extraction_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_extraction_history_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result extraction_history_create(ke_extraction* extraction, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* fixed_pre_update, [NativeTypeName("ke_schedule_set_id")] uint fixed_pre_update_set, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_module);

    [DllImport("ke_extraction_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_extraction_default_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* extraction_default_parts([NativeTypeName("size_t *")] nuint* out_count);
}
