using KernelEngine.Common.Native;

namespace KernelEngine.Scheduler.Enki.Native;

public partial struct ke_scheduler_enki_params
{
    [NativeTypeName("uint32_t")]
    public uint worker_count;
}
