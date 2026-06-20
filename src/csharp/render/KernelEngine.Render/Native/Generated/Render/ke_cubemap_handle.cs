using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_cubemap_handle
{
    [NativeTypeName("uint32_t")]
    public uint idx;
}
