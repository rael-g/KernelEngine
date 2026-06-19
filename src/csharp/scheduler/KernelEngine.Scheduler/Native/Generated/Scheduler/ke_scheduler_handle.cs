using KernelEngine.Common.Native;

namespace KernelEngine.Scheduler.Native;

public unsafe partial struct ke_scheduler_handle
{
    public ke_scheduler* @ref;

    [NativeTypeName("void (*)(ke_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_scheduler*, void> destroy;
}
