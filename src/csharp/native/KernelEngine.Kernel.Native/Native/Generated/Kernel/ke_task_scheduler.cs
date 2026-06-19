namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_task_scheduler
{
    public void* handle;

    [NativeTypeName("ke_task *(*)(struct ke_task_scheduler *, ke_task_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_task_scheduler*, delegate* unmanaged[Cdecl]<void*, void>, void*, ke_task*> dispatch;

    [NativeTypeName("ke_task *(*)(struct ke_task_scheduler *, ke_task_func, void *, ke_task_on_complete_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_task_scheduler*, delegate* unmanaged[Cdecl]<void*, void>, void*, delegate* unmanaged[Cdecl]<ke_task*, void*, void>, void*, ke_task*> dispatch_on_complete;

    [NativeTypeName("void (*)(struct ke_task_scheduler *, ke_task *)")]
    public delegate* unmanaged[Cdecl]<ke_task_scheduler*, ke_task*, void> wait;

    [NativeTypeName("bool (*)(struct ke_task_scheduler *, ke_task *)")]
    public delegate* unmanaged[Cdecl]<ke_task_scheduler*, ke_task*, bool> is_completed;

    [NativeTypeName("ke_task *(*)(struct ke_task_scheduler *, uint32_t, ke_task_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_task_scheduler*, uint, delegate* unmanaged[Cdecl]<void*, void>, void*, ke_task*> dispatch_pinned;

    [NativeTypeName("uint32_t (*)(struct ke_task_scheduler *)")]
    public delegate* unmanaged[Cdecl]<ke_task_scheduler*, uint> get_num_workers;
}

public partial struct ke_task_scheduler
{
}
