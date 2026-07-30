using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_alpha_mode : uint
{
    KE_ALPHA_MODE_OPAQUE,
    KE_ALPHA_MODE_MASK,
    KE_ALPHA_MODE_BLEND,
}
