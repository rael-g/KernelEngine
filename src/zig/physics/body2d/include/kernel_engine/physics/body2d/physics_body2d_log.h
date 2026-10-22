#ifndef KERNEL_ENGINE_PHYSICS_BODY2D_PHYSICS_BODY2D_LOG_H_
#define KERNEL_ENGINE_PHYSICS_BODY2D_PHYSICS_BODY2D_LOG_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/logger/log_callback.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_PHYSICS_BODY2D_API
#  ifdef KE_PHYSICS_BODY2D_EXPORT
#    define KE_PHYSICS_BODY2D_API KE_EXPORT
#  else
#    define KE_PHYSICS_BODY2D_API KE_IMPORT
#  endif
#endif

/**
 * Sends every line ke_physics_body2d logs to @p callback, with @p ctx; a NULL callback sends them back to
 * stderr, where they go until this is called. Called once, before the library logs.
 * @param callback [callback,optional] Receives each line.
 * @param ctx [context] Handed to @p callback unchanged.
 */
KE_PHYSICS_BODY2D_API void ke_physics_body2d_set_log_callback(ke_log_callback callback, void *ctx);

#ifdef __cplusplus
}
#endif

#endif
