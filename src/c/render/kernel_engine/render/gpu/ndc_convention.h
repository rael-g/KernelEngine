#ifndef KERNEL_ENGINE_RENDER_GPU_NDC_CONVENTION_H_
#define KERNEL_ENGINE_RENDER_GPU_NDC_CONVENTION_H_

#include <kernel_engine/common/types.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_ndc_convention
    {
        ke_bool z_zero_to_one; ///< 1 = clip z in [0,1] (Vulkan/D3D/WebGPU), 0 = [-1,1] (GL)
        ke_bool y_flip;        ///< 1 = framebuffer origin top-left needs Y flip in projection
        ke_bool clip_left_handed; ///< 1 = left-handed clip space, 0 = right-handed
    } ke_ndc_convention;

#ifdef __cplusplus
}
#endif

#endif
