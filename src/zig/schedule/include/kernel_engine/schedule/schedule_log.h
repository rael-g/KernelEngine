#ifndef KERNEL_ENGINE_SCHEDULE_SCHEDULE_LOG_H_
#define KERNEL_ENGINE_SCHEDULE_SCHEDULE_LOG_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/logger/log_callback.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_SCHEDULE_CREATE_API
#  ifdef KE_SCHEDULE_CREATE_EXPORT
#    define KE_SCHEDULE_CREATE_API KE_EXPORT
#  else
#    define KE_SCHEDULE_CREATE_API KE_IMPORT
#  endif
#endif

/**
 * Sends every line ke_schedule logs to @p callback, with @p ctx; a NULL callback sends them back to
 * stderr, where they go until this is called. Called once, before the library logs.
 * @param callback [callback,optional] Receives each line.
 * @param ctx [context] Handed to @p callback unchanged.
 */
KE_SCHEDULE_CREATE_API void ke_schedule_set_log_callback(ke_log_callback callback, void *ctx);

#ifdef __cplusplus
}
#endif

#endif
