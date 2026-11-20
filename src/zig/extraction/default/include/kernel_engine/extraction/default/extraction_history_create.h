#ifndef KERNEL_ENGINE_EXTRACTION_DEFAULT_EXTRACTION_HISTORY_CREATE_H_
#define KERNEL_ENGINE_EXTRACTION_DEFAULT_EXTRACTION_HISTORY_CREATE_H_

#include <kernel_engine/extraction/extraction.h>
#include <kernel_engine/extraction/default/extraction_default_log.h>
#include <kernel_engine/assembly/part.h>
#include <kernel_engine/scheduling/schedule.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Creates the module that keeps the previous value of every interpolation of @p extraction: it registers, in
 * @p fixed_pre_update_set of @p fixed_pre_update, one system per interpolation registered before or after, which
 * copies each entity's current value into its previous one before the step. Destroying the module removes them.
 * @param extraction [borrowed] Created by ke_extraction_create; must outlive the module.
 * @param fixed_pre_update [borrowed] Must outlive the module.
 * @param fixed_pre_update_set The set of @p fixed_pre_update the systems join.
 * @param out_module [out] Receives the module; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument or an extraction this library did not create;
 *         KE_RESULT_NOT_SUPPORTED while another history module of @p extraction lives; the code the schedule
 *         refused a system with, nothing left registered.
 */
KE_EXTRACTION_DEFAULT_API ke_result ke_extraction_history_create(
    ke_extraction      *extraction,
    ke_schedule        *fixed_pre_update,
    ke_schedule_set_id  fixed_pre_update_set,
    ke_owner           *out_module);

#ifdef __cplusplus
}
#endif

#endif
