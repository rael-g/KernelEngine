using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Schedule;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Schedule.Native;

public unsafe partial struct ke_schedule_handle
{
    public ke_schedule* @ref;

    [NativeTypeName("void (*)(ke_schedule *)")]
    public delegate* unmanaged[Cdecl]<ke_schedule*, void> destroy;
}
