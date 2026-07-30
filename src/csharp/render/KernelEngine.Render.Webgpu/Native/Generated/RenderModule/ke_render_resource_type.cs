using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum ke_render_resource_type : uint
{
    KE_RENDER_RESOURCE_TEXTURE = 0,
    KE_RENDER_RESOURCE_BUFFER = 1,
}
