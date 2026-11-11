using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.TaskPool.Native;

public partial struct ke_task_pool_config
{
    [NativeTypeName("uint32_t")]
    public uint worker_count;
}
