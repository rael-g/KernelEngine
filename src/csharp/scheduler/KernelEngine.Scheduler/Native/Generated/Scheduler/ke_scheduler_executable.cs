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

public unsafe partial struct ke_scheduler_executable
{
    [NativeTypeName("ke_scheduler_run_fn")]
    public delegate* unmanaged[Cdecl]<void*, float, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result> run;

    public void* user;
}
