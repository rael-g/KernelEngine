#ifndef KERNEL_ENGINE_KERNEL_LOGGER_LOGGER_H_
#define KERNEL_ENGINE_KERNEL_LOGGER_LOGGER_H_

#include <kernel_engine/kernel/common/descriptor.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/logger/log_level.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_LOGGER "ke_logger"

    /// @brief Data structure representing a single log entry.
    typedef struct ke_log_event
    {
        int level;
        const char *tag;
        const char *message;
    } ke_log_event;

    /// @brief Output target for log messages.
    typedef struct ke_logger_sink
    {
        void *handle;
        int min_level; ///< Events below this level are skipped by the logger before calling log().
        void (*log)(struct ke_logger_sink *self, const ke_log_event *event);
        void (*destroy)(struct ke_logger_sink *self);
    } ke_logger_sink;

    /// @brief Engine logging system.
    typedef struct ke_logger
    {
        void *handle;
        int runtime_limit;

        struct ke_allocator *allocator;

        void (*destroy)(struct ke_logger *self);

        /**
         * @brief Dispatches a log event to all registered sinks.
         */
        void (*log)(struct ke_logger *self, const ke_log_event *event);
        
        ke_result (*add_sink)(struct ke_logger *self, ke_logger_sink sink);

    } ke_logger;

    /// @brief Creates a logger instance.
    KE_API ke_result ke_logger_create(const ke_descriptor *desc, ke_logger **out_logger);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_LOGGER_LOGGER_H_
