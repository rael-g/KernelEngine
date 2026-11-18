#ifndef KERNEL_ENGINE_IO_INLINE_IO_INLINE_LOG_H_
#define KERNEL_ENGINE_IO_INLINE_IO_INLINE_LOG_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/logger/log_callback.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_IO_INLINE_API
#  ifdef KE_IO_INLINE_EXPORT
#    define KE_IO_INLINE_API KE_EXPORT
#  else
#    define KE_IO_INLINE_API KE_IMPORT
#  endif
#endif

/**
 * Sends every line ke_io_inline logs to @p callback, with @p ctx; a NULL callback sends them back to
 * stderr, where they go until this is called. Called once, before the library logs.
 * @param callback [callback,optional] Receives each line.
 * @param ctx [context] Handed to @p callback unchanged.
 */
KE_IO_INLINE_API void ke_io_inline_set_log_callback(ke_log_callback callback, void *ctx);

#ifdef __cplusplus
}
#endif

#endif
