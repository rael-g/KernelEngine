using KernelEngine.Result.Native;

namespace KernelEngine.TaskPool.Native;

public unsafe partial struct ke_task_pool
{
    public void* handle;

    [NativeTypeName("ke_task *(*)(struct ke_task_pool *, ke_task_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, delegate* unmanaged[Cdecl]<void*, KernelEngine.Result.Native.ke_result>, void*, ke_task*> dispatch;

    [NativeTypeName("ke_task *(*)(struct ke_task_pool *, ke_task_func, void *, ke_task_on_complete_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, delegate* unmanaged[Cdecl]<void*, KernelEngine.Result.Native.ke_result>, void*, delegate* unmanaged[Cdecl]<ke_task*, void*, KernelEngine.Result.Native.ke_result, void>, void*, ke_task*> dispatch_on_complete;

    [NativeTypeName("ke_result (*)(struct ke_task_pool *, ke_task *)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, ke_task*, KernelEngine.Result.Native.ke_result> wait;

    [NativeTypeName("bool (*)(struct ke_task_pool *, ke_task *)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, ke_task*, bool> is_completed;

    [NativeTypeName("uint32_t (*)(struct ke_task_pool *)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, uint> get_num_workers;
}
