#ifndef KERNEL_ENGINE_LOGGER_LOG_CALLBACK_H_
#define KERNEL_ENGINE_LOGGER_LOG_CALLBACK_H_

#include <kernel_engine/logger/log_level.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /**
     * Receives one line a plugin library logged. Each plugin library exports
     * `<library>_set_log_callback(ke_log_callback callback, void *ctx)`, declared in its `log.h`;
     * the host sets it once, before the library logs, and a NULL callback sends the library's lines
     * to stderr, which is also where they go until it is set. Called on whichever thread logged.
     * @param ctx [context] The pointer given to the setter, unchanged.
     * @param level How severe the line is: error, warning, info or debug.
     * @param scope [borrowed,utf8] The name of what logged: the plugin, or a third-party library
     *        it routes. Valid only during the call.
     * @param message [borrowed,utf8] The formatted line. Valid only during the call.
     */
    typedef void (*ke_log_callback)(void *ctx, ke_log_level level, const char *scope, const char *message);

#ifdef __cplusplus
}
#endif

#endif
