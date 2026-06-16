namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_ecs_registry
{
    [NativeTypeName("ke_entity")]
    public ulong next_entity;

    public void* internal_data;
}
