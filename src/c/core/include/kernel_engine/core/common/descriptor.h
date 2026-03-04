#ifndef KERNEL_ENGINE_CORE_COMMON_DESCRIPTOR_H_
#define KERNEL_ENGINE_CORE_COMMON_DESCRIPTOR_H_

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

#endif // KERNEL_ENGINE_CORE_COMMON_DESCRIPTOR_H_
