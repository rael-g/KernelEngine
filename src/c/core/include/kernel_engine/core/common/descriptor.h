#pragma once

#ifdef __cplusplus
extern "C"
{
#endif

    struct ke_allocator;
    struct ke_logger;
    struct ke_message_pipe;

    /// @brief Generic descriptor for object creation.
    typedef struct ke_descriptor
    {
        struct ke_allocator *allocator;
        struct ke_logger *logger;
        struct ke_message_pipe *message_pipe;
    } ke_descriptor;

#ifdef __cplusplus
}
#endif
