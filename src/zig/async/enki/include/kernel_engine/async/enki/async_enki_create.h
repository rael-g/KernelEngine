#ifndef KERNEL_ENGINE_ASYNC_ENKI_ASYNC_ENKI_CREATE_H_
#define KERNEL_ENGINE_ASYNC_ENKI_ASYNC_ENKI_CREATE_H_

#include <kernel_engine/configuration/settings.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/async/async.h>

#ifdef __cplusplus
extern "C" {
#endif


#ifndef KE_ASYNC_ENKI_CREATE_API
#  ifdef KE_ASYNC_ENKI_CREATE_EXPORT
#    define KE_ASYNC_ENKI_CREATE_API KE_EXPORT
#  else
#    define KE_ASYNC_ENKI_CREATE_API KE_IMPORT
#  endif
#endif

/**
 * Creates an async system on enkiTS, its workers started.
 * @param settings [borrowed] Read once. KE_ASYNC_SETTING_WORKER_COUNT, default 2; `submit_capacity`,
 *        an integer, default 1024: how many submissions from other threads may wait for the next drain.
 * @param out_async [out] Receives the async system; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p settings or @p out_async, or a setting that is
 *         unknown, of another type, or a submit_capacity of zero;
 *         KE_RESULT_OUT_OF_MEMORY; KE_RESULT_GENERAL when the workers cannot be started.
 */
KE_ASYNC_ENKI_CREATE_API ke_result ke_async_enki_create(ke_settings *settings, ke_async_handle *out_async);

#ifdef __cplusplus
}
#endif

#endif
