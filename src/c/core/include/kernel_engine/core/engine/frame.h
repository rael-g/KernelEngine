#ifndef KERNEL_ENGINE_CORE_ENGINE_FRAME_H_
#define KERNEL_ENGINE_CORE_ENGINE_FRAME_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Data associated with a single engine simulation step.
    typedef struct ke_frame
    {
        uint64_t frame_index;
        double delta_time;
        double total_time;
    } ke_frame;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_CORE_ENGINE_FRAME_H_
