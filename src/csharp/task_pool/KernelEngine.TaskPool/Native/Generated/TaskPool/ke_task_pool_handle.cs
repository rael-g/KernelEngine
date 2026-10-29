using KernelEngine.Result.Native;

namespace KernelEngine.TaskPool.Native;

public unsafe partial struct ke_task_pool_handle
{
    public ke_task_pool* @ref;

    [NativeTypeName("void (*)(ke_task_pool *)")]
    public delegate* unmanaged[Cdecl]<ke_task_pool*, void> destroy;
}
