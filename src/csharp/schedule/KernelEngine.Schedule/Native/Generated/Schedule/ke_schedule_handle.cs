using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Completion.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Job.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Schedule.Native;

public unsafe partial struct ke_schedule_handle
{
    public ke_schedule* @ref;

    [NativeTypeName("void (*)(ke_schedule *)")]
    public delegate* unmanaged[Cdecl]<ke_schedule*, void> destroy;
}
