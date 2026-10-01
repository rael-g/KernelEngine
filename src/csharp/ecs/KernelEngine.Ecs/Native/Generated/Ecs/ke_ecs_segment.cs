using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs_segment
{
    [NativeTypeName("const ke_entity *")]
    public ulong* entities;

    [NativeTypeName("size_t")]
    public nuint count;

    public void** columns;

    [NativeTypeName("uint32_t")]
    public uint column_count;
}
