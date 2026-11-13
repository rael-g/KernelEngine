#ifndef KERNEL_ENGINE_ASYNC_INLINE_ASYNC_INLINE_CREATE_H_
#define KERNEL_ENGINE_ASYNC_INLINE_ASYNC_INLINE_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/async/async.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_ASYNC_INLINE_CREATE_API
#  ifdef KE_ASYNC_INLINE_CREATE_EXPORT
#    define KE_ASYNC_INLINE_CREATE_API KE_EXPORT
#  else
#    define KE_ASYNC_INLINE_CREATE_API KE_IMPORT
#  endif
#endif

/**
 * Creates an async system that runs every operation on the creating thread, when it is waited on or drained.
 * @param config [borrowed] Required; every field is read as given.
 * @param out_async [out] Receives the async system; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p config or @p out_async, a worker_count other than zero, or a submit_capacity of zero;
 *         KE_RESULT_OUT_OF_MEMORY.
 */
KE_ASYNC_INLINE_CREATE_API ke_result ke_async_inline_create(const ke_async_config *config, ke_async_handle *out_async);

#ifdef __cplusplus
}
#endif

#endif
