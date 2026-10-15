using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

[NativeTypeName("unsigned int")]
public enum ke_render_binding_hint_flags : uint
{
    KE_RENDER_BINDING_HINT_DEPTH = 0x1U,
    KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET = 0x2U,
}
