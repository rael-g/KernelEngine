#ifndef KERNEL_ENGINE_EXTRACTION_DEFAULT_EXTRACTION_CREATE_H_
#define KERNEL_ENGINE_EXTRACTION_DEFAULT_EXTRACTION_CREATE_H_

#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/render/extraction.h>
#include <kernel_engine/extraction/default/extraction_default_log.h>
#include <kernel_engine/scheduling/scheduler.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Creates the extraction from @p main into @p render, registering its tags in each world, whose render stage
 * extracts at @p scheduler's fixed alpha. Every argument but @p out_extraction must
 * outlive the extraction.
 * @param out_extraction [out] Receives the extraction; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_OUT_OF_MEMORY; the code of the world
 *         that refused a tag.
 */
KE_EXTRACTION_DEFAULT_API ke_result ke_extraction_create(
    ke_ecs               *main,
    ke_ecs               *render,
    ke_scheduler         *scheduler,
    ke_extraction_handle *out_extraction);

#ifdef __cplusplus
}
#endif

#endif
