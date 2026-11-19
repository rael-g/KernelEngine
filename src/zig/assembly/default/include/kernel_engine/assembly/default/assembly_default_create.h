#ifndef KERNEL_ENGINE_ASSEMBLY_DEFAULT_ASSEMBLY_DEFAULT_CREATE_H_
#define KERNEL_ENGINE_ASSEMBLY_DEFAULT_ASSEMBLY_DEFAULT_CREATE_H_

#include <kernel_engine/assembly/assembly.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/configuration/configuration.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_ASSEMBLY_DEFAULT_API
#  ifdef KE_ASSEMBLY_DEFAULT_EXPORT
#    define KE_ASSEMBLY_DEFAULT_API KE_EXPORT
#  else
#    define KE_ASSEMBLY_DEFAULT_API KE_IMPORT
#  endif
#endif

/**
 * Creates an assembly on the calling thread: it resolves, creates and destroys on whichever thread calls it, one
 * call at a time.
 * @param configuration [borrowed] Each instance reads its section from it; must outlive the assembly.
 * @param out_assembly [out] Receives the assembly; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p configuration or @p out_assembly;
 *         KE_RESULT_OUT_OF_MEMORY.
 */
KE_ASSEMBLY_DEFAULT_API ke_result ke_assembly_default_create(ke_configuration *configuration,
                                                             ke_assembly_handle *out_assembly);

#ifdef __cplusplus
}
#endif

#endif
