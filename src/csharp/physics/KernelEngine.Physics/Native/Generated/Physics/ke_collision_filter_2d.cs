using KernelEngine.Common.Native;

namespace KernelEngine.Physics.Native;

public partial struct ke_collision_filter_2d
{
    [NativeTypeName("uint32_t")]
    public uint layer;

    [NativeTypeName("uint32_t")]
    public uint mask;
}
