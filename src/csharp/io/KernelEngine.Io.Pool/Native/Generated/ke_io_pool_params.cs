using KernelEngine.FileSystem.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Io.Pool.Native;

public unsafe partial struct ke_io_pool_params
{
    [NativeTypeName("ke_task_pool *")]
    public KernelEngine.TaskPool.Native.ke_task_pool* task_pool;

    [NativeTypeName("ke_file_system *")]
    public KernelEngine.FileSystem.Native.ke_file_system* file_system;
}
