#ifndef KERNEL_ENGINE_KERNEL_ENGINE_SYSTEM_H_
#define KERNEL_ENGINE_KERNEL_ENGINE_SYSTEM_H_

#include <kernel_engine/kernel/common/error.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

    struct ke_world;
    struct ke_frame_packet;

    /**
     * @brief Signature for a system's update logic.
     * @param handle User-defined context pointer.
     * @param world  The active simulation world.
     * @param dt     Delta time since the last frame.
     * @param packet The frame packet for recording render commands (optional).
     */
    typedef void (*ke_system_update_func)(void* handle, struct ke_world* world, float dt, struct ke_frame_packet* packet);

    /**
     * @brief Description used to register a system in the Kernel.
     * Declarative dependencies allow the scheduler to run non-conflicting systems in parallel.
     */
    typedef struct ke_system_desc {
        const char*           name;
        ke_system_update_func update;
        void*                 handle;

        // Component access for wave-based scheduling
        const uint32_t*       reads;
        uint32_t              read_count;
        const uint32_t*       writes;
        uint32_t              write_count;
    } ke_system_desc;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_ENGINE_SYSTEM_H_
