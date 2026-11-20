using System.Numerics;

using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Async.Native;
using KernelEngine.Completion.Native;
using KernelEngine.Job.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Scheduler.Native;

public unsafe partial struct ke_scheduler
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_scheduler *, ke_scheduler_run_fn, void *, ke_scheduler_cadence)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, delegate* unmanaged[Cdecl]<void*, float, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result>, void*, global::KernelEngine.Scheduler.SchedulerCadence, KernelEngine.Result.Native.Result> add;

    [NativeTypeName("ke_result (*)(ke_scheduler *, float)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, float, KernelEngine.Result.Native.Result> tick;

    [NativeTypeName("ke_result (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, KernelEngine.Result.Native.Result> shutdown;

    [NativeTypeName("void (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, void> request_exit;

    [NativeTypeName("bool (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, bool> exit_requested;

    [NativeTypeName("uint64_t (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, ulong> sequence;

    [NativeTypeName("bool (*)(ke_scheduler *, const void *, uint64_t)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, void*, ulong, bool> completed_since;

    [NativeTypeName("float (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, float> fixed_alpha;
}
