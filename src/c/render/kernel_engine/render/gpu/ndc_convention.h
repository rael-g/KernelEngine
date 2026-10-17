#ifndef KERNEL_ENGINE_RENDER_GPU_NDC_CONVENTION_H_
#define KERNEL_ENGINE_RENDER_GPU_NDC_CONVENTION_H_

#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_ndc_convention
    {
        bool z_zero_to_one;    ///< True when clip z is in [0,1] (Vulkan/D3D/WebGPU), false for [-1,1] (GL).
        bool y_flip;           ///< True when a top-left framebuffer origin needs a Y flip in projection.
        bool clip_left_handed; ///< True for a left-handed clip space, false for right-handed.
    } ke_ndc_convention;

#ifdef __cplusplus
}
#endif

#endif
