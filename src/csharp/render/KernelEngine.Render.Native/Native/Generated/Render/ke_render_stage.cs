using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

[NativeTypeName("unsigned int")]
public enum ke_render_stage : uint
{
    KE_RENDER_STAGE_OPAQUE = 0,
    KE_RENDER_STAGE_SKY = 1,
    KE_RENDER_STAGE_TRANSPARENT = 2,
    KE_RENDER_STAGE_HDR_POST = 3,
    KE_RENDER_STAGE_TONEMAP = 4,
    KE_RENDER_STAGE_LDR_POST = 5,
    KE_RENDER_STAGE_OVERLAY = 6,
    KE_RENDER_STAGE_COUNT = 7,
}
