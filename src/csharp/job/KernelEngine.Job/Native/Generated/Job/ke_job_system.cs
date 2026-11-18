using System.Numerics;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Job.Native;

public unsafe partial struct ke_job_system
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_job_system *, const char *, ke_job_fn, void *, ke_completion *const *, uint32_t, ke_completion **)")]
    public delegate* unmanaged[Cdecl]<ke_job_system*, sbyte*, delegate* unmanaged[Cdecl]<void*, JobCtx*, KernelEngine.Result.Native.Result>, void*, KernelEngine.Completion.Native.ke_completion**, uint, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result> dispatch;

    [NativeTypeName("ke_result (*)(ke_job_system *, const char *, ke_job_range_fn, void *, uint32_t, uint32_t, ke_completion *const *, uint32_t, ke_completion **)")]
    public delegate* unmanaged[Cdecl]<ke_job_system*, sbyte*, delegate* unmanaged[Cdecl]<void*, uint, uint, uint, KernelEngine.Result.Native.Result>, void*, uint, uint, KernelEngine.Completion.Native.ke_completion**, uint, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result> parallel_for;

    [NativeTypeName("uint32_t (*)(ke_job_system *)")]
    public delegate* unmanaged[Cdecl]<ke_job_system*, uint> worker_slots;

    [NativeTypeName("void (*)(ke_job_system *)")]
    public delegate* unmanaged[Cdecl]<ke_job_system*, void> drain;
}
