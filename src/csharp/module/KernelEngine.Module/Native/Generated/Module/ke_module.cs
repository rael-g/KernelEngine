using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;

namespace KernelEngine.Module.Native;

public unsafe partial struct ke_module
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_module *, const ke_module_targets *)")]
    public delegate* unmanaged[Cdecl]<ke_module*, ke_module_targets*, KernelEngine.Result.Native.Result> attach;

    [NativeTypeName("void (*)(ke_module *)")]
    public delegate* unmanaged[Cdecl]<ke_module*, void> detach;
}
