using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_material_handle
{
    [NativeTypeName("uint32_t")]
    public uint bits;
}
