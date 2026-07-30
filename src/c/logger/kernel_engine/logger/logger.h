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

    /**
     * Output target for log messages. Implemented by the caller and handed to a
     * logger; the logger owns it from that point and calls destroy on teardown.
     */
    typedef struct ke_logger_sink
    {
        void   *handle;
        int32_t min_level;
        /**
         * Receives one log entry that passed this sink's level filter.
         * @param event [borrowed] Entry to write. Not valid after the call returns.
         */
        void (*log)(struct ke_logger_sink *self, const ke_log_event *event);

        /** Flushes any buffered output. */
        void (*flush)(struct ke_logger_sink *self);

        /** Releases the sink. Called by the logger that took ownership. */
        void (*destroy)(struct ke_logger_sink *self);
    } ke_logger_sink;

    /// @brief Engine logging system.
    typedef struct ke_logger
    {
        void *handle;
        void (*log)(struct ke_logger *self, const ke_log_event *event);
        void (*flush)(struct ke_logger *self);
        /**
         * Takes ownership of a sink and starts routing entries to it.
         * @param sink [callback] Caller-implemented output target.
         */
        bool (*add_sink)(struct ke_logger *self, ke_logger_sink sink, ke_error **out_error);
    } ke_logger;

    typedef struct ke_logger_handle
    {
        ke_logger *ref;
        void (*destroy)(ke_logger *self);
    } ke_logger_handle;

    /// @brief Creates a logger instance.
    KE_LOGGER_API ke_logger_handle ke_logger_create(ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_LOGGER_LOGGER_H_
