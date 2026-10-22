#ifndef KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_LOG_H_
#define KERNEL_ENGINE_RENDER_SERVICE_RENDER_SERVICE_LOG_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/logger/log_callback.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_RENDER_CORE_API
#  ifdef KE_RENDER_CORE_EXPORT
#    define KE_RENDER_CORE_API KE_EXPORT
#  else
#    define KE_RENDER_CORE_API KE_IMPORT
#  endif
#endif

/**
 * Sends every line ke_render_service logs to @p callback, with @p ctx; a NULL callback sends them back to
 * stderr, where they go until this is called. Called once, before the library logs.
 * @param callback [callback,optional] Receives each line.
 * @param ctx [context] Handed to @p callback unchanged.
 */
KE_RENDER_CORE_API void ke_render_service_set_log_callback(ke_log_callback callback, void *ctx);

#ifdef __cplusplus
}
#endif

#endif
