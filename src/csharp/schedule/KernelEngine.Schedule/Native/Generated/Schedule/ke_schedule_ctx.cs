using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Schedule;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Schedule.Native;

public unsafe partial struct ke_schedule_ctx
{
    public void* handle;

    [NativeTypeName("ke_ecs_commands *")]
    public KernelEngine.Ecs.Native.ke_ecs_commands* commands;

    [NativeTypeName("const ke_ecs_segment *(*)(ke_schedule_ctx *, uint32_t, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_schedule_ctx*, uint, nuint*, KernelEngine.Ecs.Native.ke_ecs_segment*> view;

    [NativeTypeName("void (*)(ke_schedule_ctx *, uint32_t *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_schedule_ctx*, uint*, uint*, void> slice;
}
