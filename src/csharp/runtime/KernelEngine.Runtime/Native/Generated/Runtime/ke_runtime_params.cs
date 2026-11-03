using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Runtime;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Runtime.Native;

public partial struct ke_runtime_params
{
    public float fixed_dt;

    public float fixed_dt_max_accum;

    [NativeTypeName("uint32_t")]
    public uint max_systems_per_phase;
}
