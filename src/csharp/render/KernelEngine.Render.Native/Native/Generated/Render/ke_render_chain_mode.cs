using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

[NativeTypeName("unsigned int")]
public enum ke_render_chain_mode : uint
{
    KE_RENDER_CHAIN_DRAW_OVER = 0,
    KE_RENDER_CHAIN_SAMPLE_OVER = 1,
    KE_RENDER_CHAIN_REPLACE = 2,
}
