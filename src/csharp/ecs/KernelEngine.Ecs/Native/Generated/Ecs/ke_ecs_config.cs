using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public partial struct ke_ecs_config
{
    [NativeTypeName("uint32_t")]
    public uint reserved_id_capacity;
}
