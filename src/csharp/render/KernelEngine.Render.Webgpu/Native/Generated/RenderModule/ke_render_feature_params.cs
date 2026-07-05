using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_render_feature_params
{
    [NativeTypeName("ke_bool")]
    public byte enable_shadows;

    [NativeTypeName("ke_bool")]
    public byte enable_ibl;
}
