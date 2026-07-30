using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_render_size_mode : uint
{
    KE_RENDER_SIZE_ABSOLUTE = 0,
    KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER = 1,
}
