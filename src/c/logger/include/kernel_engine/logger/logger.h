#ifndef KERNEL_ENGINE_LOGGER_LOGGER_H_
#define KERNEL_ENGINE_LOGGER_LOGGER_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/logger/log_level.h>

#ifdef __cplusplus
extern "C"
{
#endif

typedef struct ke_logger ke_logger;

#define KE_ID_LOGGER "ke_logger"

    /// @brief Data structure representing a single log entry.
    typedef struct ke_log_event
    {
        int32_t     level;
        const char *tag;
        const char *message;
    } ke_log_event;

    /// @brief Output target for log messages.
    typedef struct ke_logger_sink
    {
        void   *handle;
        int32_t min_level;
        void (*log)(struct ke_logger_sink *self, const ke_log_event *event);
        void (*flush)(struct ke_logger_sink *self);
        void (*destroy)(struct ke_logger_sink *self);
    } ke_logger_sink;

    /// @brief Engine logging system.
    typedef struct ke_logger
    {
        void *handle;
        void (*destroy)(struct ke_logger *self);
        void (*log)(struct ke_logger *self, const ke_log_event *event);
        void (*flush)(struct ke_logger *self);
        ke_result (*add_sink)(struct ke_logger *self, ke_logger_sink sink, ke_error **out_error);
    } ke_logger;

    /// @brief Creates a logger instance.
    KE_LOGGER_API ke_result ke_logger_create(ke_logger **out_logger, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_LOGGER_LOGGER_H_
