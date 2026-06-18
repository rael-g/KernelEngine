namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_task_scheduler_handle
{
    public ke_task_scheduler* @ref;

    [NativeTypeName("void (*)(ke_task_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_task_scheduler*, void> destroy;
}
