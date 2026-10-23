using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_shadow_map_handle
{
    [NativeTypeName("uint32_t")]
    public uint bits;
}
