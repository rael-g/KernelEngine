using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Flecs.Native;

public partial struct ke_ecs_flecs_params
{
    [NativeTypeName("uint32_t")]
    public uint world_id_base;
}
