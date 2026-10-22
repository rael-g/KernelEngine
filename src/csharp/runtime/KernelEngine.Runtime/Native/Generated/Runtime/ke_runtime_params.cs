using KernelEngine.Common.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Runtime.Native;

public partial struct ke_runtime_params
{
    public float fixed_dt;

    public float fixed_dt_max_accum;

    [NativeTypeName("uint32_t")]
    public uint max_systems_per_phase;
}
