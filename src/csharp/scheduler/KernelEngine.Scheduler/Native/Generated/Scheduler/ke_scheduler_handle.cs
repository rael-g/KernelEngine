using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Scheduler.Native;

public unsafe partial struct ke_scheduler_handle
{
    public ke_scheduler* @ref;

    [NativeTypeName("void (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, void> destroy;
}
