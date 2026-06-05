#ifndef KERNEL_ENGINE_KERNEL_ENGINE_FRAME_H_
#define KERNEL_ENGINE_KERNEL_ENGINE_FRAME_H_

#include <kernel_engine/kernel/input/snapshot.h>
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
        const ke_input_snapshot *input; // optional; NULL when no input is available
    } ke_frame;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_ENGINE_FRAME_H_
