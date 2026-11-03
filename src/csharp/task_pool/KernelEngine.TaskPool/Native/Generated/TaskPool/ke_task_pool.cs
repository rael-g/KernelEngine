using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.TaskPool.Native;

public unsafe partial struct ke_task_pool
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_task_pool *, ke_task_func, void *, ke_task **)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, delegate* unmanaged[Cdecl]<void*, KernelEngine.Result.Native.Result>, void*, ke_task**, KernelEngine.Result.Native.Result> dispatch;

    [NativeTypeName("ke_result (*)(struct ke_task_pool *, ke_task_func, void *, ke_task_on_complete_func, void *, ke_task **)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, delegate* unmanaged[Cdecl]<void*, KernelEngine.Result.Native.Result>, void*, delegate* unmanaged[Cdecl]<ke_task*, void*, KernelEngine.Result.Native.Result, void>, void*, ke_task**, KernelEngine.Result.Native.Result> dispatch_on_complete;

    [NativeTypeName("ke_result (*)(struct ke_task_pool *, ke_task *)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, ke_task*, KernelEngine.Result.Native.Result> wait;

    [NativeTypeName("bool (*)(struct ke_task_pool *, ke_task *)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, ke_task*, bool> is_completed;

    [NativeTypeName("uint32_t (*)(struct ke_task_pool *)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, uint> get_num_workers;
}
