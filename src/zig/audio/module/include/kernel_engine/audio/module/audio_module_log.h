#ifndef KERNEL_ENGINE_AUDIO_MODULE_AUDIO_MODULE_LOG_H_
#define KERNEL_ENGINE_AUDIO_MODULE_AUDIO_MODULE_LOG_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/logger/log_callback.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_AUDIO_MODULE_API
#  ifdef KE_AUDIO_MODULE_EXPORT
#    define KE_AUDIO_MODULE_API KE_EXPORT
#  else
#    define KE_AUDIO_MODULE_API KE_IMPORT
#  endif
#endif

/**
 * Sends every line ke_audio_module logs to @p callback, with @p ctx; a NULL callback sends them back to
 * stderr, where they go until this is called. Called once, before the library logs.
 * @param callback [callback,optional] Receives each line.
 * @param ctx [context] Handed to @p callback unchanged.
 */
KE_AUDIO_MODULE_API void ke_audio_module_set_log_callback(ke_log_callback callback, void *ctx);

#ifdef __cplusplus
}
#endif

#endif
