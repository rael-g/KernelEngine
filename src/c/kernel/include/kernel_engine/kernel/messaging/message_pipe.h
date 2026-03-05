#ifndef KERNEL_ENGINE_KERNEL_MESSAGING_MESSAGE_PIPE_H_
#define KERNEL_ENGINE_KERNEL_MESSAGING_MESSAGE_PIPE_H_

#include <kernel_engine/kernel/common/descriptor.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/types.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_MESSAGE_PIPE "ke_message_pipe"

    /// @brief Communication channel for broadcasting and receiving messages.
    typedef struct ke_message_pipe
    {
        void *handle;

        struct ke_allocator *allocator;
        struct ke_logger *logger;

        void (*destroy)(struct ke_message_pipe *self);

        ke_result (*broadcast)(struct ke_message_pipe *self, uint64_t msg_id, const void *data, size_t size);
        ke_result (*create_reader)(struct ke_message_pipe *self, struct ke_message_pipe **out_reader);
        bool (*try_receive)(struct ke_message_pipe *self, uint64_t msg_id, void *out_data, size_t max_size);
        ke_result (*pump)(struct ke_message_pipe *self);
    } ke_message_pipe;

    /// @brief Creates a message pipe.
    KE_API ke_result ke_message_pipe_create(const ke_descriptor *desc, ke_message_pipe **out_pipe);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_MESSAGING_MESSAGE_PIPE_H_
