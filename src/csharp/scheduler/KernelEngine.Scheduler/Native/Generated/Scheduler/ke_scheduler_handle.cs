using System.Numerics;

using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Async.Native;
using KernelEngine.Completion.Native;
using KernelEngine.Job.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Scheduler.Native;

public unsafe partial struct ke_scheduler_handle
{
    public ke_scheduler* @ref;

    [NativeTypeName("void (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, void> destroy;
}
