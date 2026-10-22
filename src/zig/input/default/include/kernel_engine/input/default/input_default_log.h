#ifndef KERNEL_ENGINE_INPUT_DEFAULT_INPUT_DEFAULT_LOG_H_
#define KERNEL_ENGINE_INPUT_DEFAULT_INPUT_DEFAULT_LOG_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/logger/log_callback.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_INPUT_DEFAULT_API
#  ifdef KE_INPUT_DEFAULT_EXPORT
#    define KE_INPUT_DEFAULT_API KE_EXPORT
#  else
#    define KE_INPUT_DEFAULT_API KE_IMPORT
#  endif
#endif

/**
 * Sends every line ke_input_default logs to @p callback, with @p ctx; a NULL callback sends them back to
 * stderr, where they go until this is called. Called once, before the library logs.
 * @param callback [callback,optional] Receives each line.
 * @param ctx [context] Handed to @p callback unchanged.
 */
KE_INPUT_DEFAULT_API void ke_input_default_set_log_callback(ke_log_callback callback, void *ctx);

#ifdef __cplusplus
}
#endif

#endif
