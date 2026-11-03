using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.TaskPool.Enki.Native;

public partial struct ke_task_pool_enki_params
{
    [NativeTypeName("uint32_t")]
    public uint worker_count;
}
