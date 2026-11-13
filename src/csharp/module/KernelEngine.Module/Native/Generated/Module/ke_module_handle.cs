using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;

namespace KernelEngine.Module.Native;

public unsafe partial struct ke_module_handle
{
    public ke_module* @ref;

    [NativeTypeName("void (*)(ke_module *)")]
    public delegate* unmanaged[Cdecl]<ke_module*, void> destroy;
}
