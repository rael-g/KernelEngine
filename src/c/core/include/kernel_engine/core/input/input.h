#pragma once

#include <kernel_engine/core/common/descriptor.h>
#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/types.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_INPUT "ke_input"

    /// @brief System responsible for keyboard and mouse state tracking.
    typedef struct ke_input
    {
        void *handle;

        struct ke_allocator *allocator;
        struct ke_logger *logger;
        struct ke_message_pipe *message_pipe;

        void (*destroy)(struct ke_input *self);

        /**
         * @brief Updates input state by reading all pending messages from the pipe.
         */
        ke_result (*update)(struct ke_input *self);

        bool (*is_key_pressed)(struct ke_input *self, int key);
        bool (*is_key_released)(struct ke_input *self, int key);
        bool (*is_key_down)(struct ke_input *self, int key);

    } ke_input;

    /// @brief Creates an input system.
    KE_API ke_result ke_input_create(const ke_descriptor *desc, ke_input **out_input);

#ifdef __cplusplus
}
#endif
