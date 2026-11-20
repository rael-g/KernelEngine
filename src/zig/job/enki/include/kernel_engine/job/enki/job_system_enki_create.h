#ifndef KERNEL_ENGINE_JOB_ENKI_JOB_SYSTEM_ENKI_CREATE_H_
#define KERNEL_ENGINE_JOB_ENKI_JOB_SYSTEM_ENKI_CREATE_H_

#include <kernel_engine/configuration/settings.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/job/job_system.h>

#ifdef __cplusplus
extern "C" {
#endif


#ifndef KE_JOB_SYSTEM_ENKI_CREATE_API
#  ifdef KE_JOB_SYSTEM_ENKI_CREATE_EXPORT
#    define KE_JOB_SYSTEM_ENKI_CREATE_API KE_EXPORT
#  else
#    define KE_JOB_SYSTEM_ENKI_CREATE_API KE_IMPORT
#  endif
#endif

/**
 * Creates a job system on enkiTS, its workers started.
 * @param settings [borrowed] Read once. KE_JOB_SYSTEM_SETTING_WORKER_COUNT, default one worker per
 *        hardware thread besides the creating one.
 * @param out_job_system [out] Receives the job system; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p settings or @p out_job_system, or a setting
 *         that is unknown or of another type;
 *         KE_RESULT_OUT_OF_MEMORY; KE_RESULT_GENERAL when the workers cannot be started.
 */
KE_JOB_SYSTEM_ENKI_CREATE_API ke_result ke_job_system_enki_create(ke_settings *settings, ke_job_system_handle *out_job_system);

#ifdef __cplusplus
}
#endif

#endif
