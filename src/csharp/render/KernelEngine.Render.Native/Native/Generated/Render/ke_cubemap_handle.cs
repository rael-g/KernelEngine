using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_cubemap_handle
{
    [NativeTypeName("uint32_t")]
    public uint bits;
}
