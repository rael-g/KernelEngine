using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

[NativeTypeName("unsigned int")]
public enum ke_render_depth_mode : uint
{
    KE_RENDER_DEPTH_NONE = 0,
    KE_RENDER_DEPTH_TEST = 1,
    KE_RENDER_DEPTH_WRITE = 2,
}
