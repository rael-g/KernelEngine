#pragma once

#include <kernel_engine/core/common/descriptor.h>
#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/types.h>
#include <kernel_engine/core/logger/log_level.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_LOGGER "ke_logger"

    /// @brief Output target for log messages.
    typedef struct ke_logger_sink
    {
        void *handle;
        void (*log)(struct ke_logger_sink *self, int level, const char *tag, const char *message);
        void (*destroy)(struct ke_logger_sink *self);
    } ke_logger_sink;

    /// @brief Engine logging system.
    typedef struct ke_logger
    {
        void *handle;
        int runtime_limit;

        struct ke_allocator *allocator;

        void (*destroy)(struct ke_logger *self);

        void (*log)(struct ke_logger *self, int level, const char *tag, const char *message);
        ke_result (*add_sink)(struct ke_logger *self, ke_logger_sink sink);

    } ke_logger;

    /// @brief Creates a logger instance.
    KE_API ke_result ke_logger_create(const ke_descriptor *desc, ke_logger **out_logger);

#ifdef __cplusplus
}
#endif
