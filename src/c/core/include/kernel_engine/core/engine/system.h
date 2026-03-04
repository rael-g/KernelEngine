#ifndef KERNEL_ENGINE_CORE_ENGINE_SYSTEM_H_
#define KERNEL_ENGINE_CORE_ENGINE_SYSTEM_H_

#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/types.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    struct ke_frame;

    /// @brief Base interface for all engine subsystems.
    typedef struct ke_system
    {
        void *handle;
        void (*destroy)(struct ke_system *self);
        ke_system_id numeric_id;
        ke_result (*on_initialize)(struct ke_system *self);
        ke_result (*on_shutdown)(struct ke_system *self);
        ke_result (*on_update)(struct ke_system *self, const struct ke_frame *frame);
    } ke_system;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_CORE_ENGINE_SYSTEM_H_
