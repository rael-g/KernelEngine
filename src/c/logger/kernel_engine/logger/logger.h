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

    /** One log entry. `tag`/`message` are valid only for the duration of the call they're passed to. */
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

    /** Engine logging system. Dispatches events to every registered sink. */
    typedef struct ke_logger
    {
        void *handle;

        /**
         * Dispatches one entry to every registered sink whose `min_level` it clears.
         * @param event [borrowed] Entry to dispatch.
         */
        void (*log)(struct ke_logger *self, const ke_log_event *event);

        /** Flushes every registered sink. */
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

    /** Creates a logger instance. */
    KE_LOGGER_API ke_logger_handle ke_logger_create(ke_error **out_error);

    /**
     * Builds a stateless sink that formats entries as `[LEVEL] tag: message`
     * and writes them to the process's standard error stream, flushing after
     * every entry. Every language wants this as a default; native so none of
     * them re-derive the format (or the level-name mapping `ke_log_level_to_string`
     * already owns).
     */
    KE_LOGGER_API ke_logger_sink ke_console_sink_create(void);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_LOGGER_LOGGER_H_
