using KernelEngine.Common.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_runtime_handle
{
    public ke_runtime* @ref;

    [NativeTypeName("void (*)(ke_runtime *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void> destroy;
}
