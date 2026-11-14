#ifndef KERNEL_ENGINE_EXTRACTION_DEFAULT_EXTRACTION_HISTORY_CREATE_H_
#define KERNEL_ENGINE_EXTRACTION_DEFAULT_EXTRACTION_HISTORY_CREATE_H_

#include <kernel_engine/extraction/extraction.h>
#include <kernel_engine/extraction/default/extraction_default_log.h>
#include <kernel_engine/module/module.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Creates the module that keeps the previous value of every interpolation of @p extraction: attaching it
 * registers, in the fixed schedule's fixed_pre_update set, one system per interpolation registered before or
 * after, which copies each entity's current value into its previous one before the step.
 * @param extraction [borrowed] Created by ke_extraction_create; must outlive the module.
 * @param out_module [out] Receives the module; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument or an extraction this library did not create.
 */
KE_EXTRACTION_DEFAULT_API ke_result ke_extraction_history_create(
    ke_extraction    *extraction,
    ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
