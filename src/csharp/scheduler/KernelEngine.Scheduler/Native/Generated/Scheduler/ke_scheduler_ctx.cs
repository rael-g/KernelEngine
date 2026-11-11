using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Scheduler;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Scheduler.Native;

public unsafe partial struct ke_scheduler_ctx
{
    public void* handle;

    [NativeTypeName("ke_ecs_commands *")]
    public KernelEngine.Ecs.Native.ke_ecs_commands* commands;

    [NativeTypeName("const ke_ecs_segment *(*)(ke_scheduler_ctx *, uint32_t, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler_ctx*, uint, nuint*, KernelEngine.Ecs.Native.ke_ecs_segment*> view;

    [NativeTypeName("void (*)(ke_scheduler_ctx *, uint32_t *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler_ctx*, uint*, uint*, void> slice;
}
