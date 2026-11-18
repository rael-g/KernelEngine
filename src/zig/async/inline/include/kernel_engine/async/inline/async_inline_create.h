#ifndef KERNEL_ENGINE_ASYNC_INLINE_ASYNC_INLINE_CREATE_H_
#define KERNEL_ENGINE_ASYNC_INLINE_ASYNC_INLINE_CREATE_H_

#include <kernel_engine/settings/settings.h>
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
 * @param settings [borrowed] Read once. KE_ASYNC_SETTING_WORKER_COUNT, default 0, the only value it
 *        accepts; `submit_capacity`, an integer, default 1024: how many submissions from other threads
 *        may wait for the next drain.
 * @param out_async [out] Receives the async system; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p settings or @p out_async, a worker_count other
 *         than zero, a submit_capacity of zero, or another setting refused;
 *         KE_RESULT_OUT_OF_MEMORY.
 */
KE_ASYNC_INLINE_CREATE_API ke_result ke_async_inline_create(ke_settings *settings, ke_async_handle *out_async);

#ifdef __cplusplus
}
#endif

#endif
