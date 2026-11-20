#ifndef KERNEL_ENGINE_ASSEMBLY_COMPOSITION_SOURCE_H_
#define KERNEL_ENGINE_ASSEMBLY_COMPOSITION_SOURCE_H_

#include <kernel_engine/assembly/assembly.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Reads a composition from somewhere outside the process into an assembly, through its composition slots
 * (add_instance, bind, order, set_default); it adds no part, since which parts exist is what the host linked. A
 * source keeps nothing between loads.
 */
typedef struct ke_composition_source
{
    void *handle;

    /**
     * Writes the composition @p path holds into @p assembly. Calls made before a failure stay; resolve reports any
     * mistake in what was written.
     * @param assembly [borrowed] The assembly written to.
     * @param path [utf8] Where the composition is read from.
     * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_NOT_FOUND when @p path holds
     *         nothing; KE_RESULT_GENERAL when the content does not parse or holds a key the source does not
     *         know; KE_RESULT_OUT_OF_MEMORY; or the code of the call to @p assembly that failed.
     */
    ke_result (*load)(struct ke_composition_source *self, ke_assembly *assembly, const char *path);
} ke_composition_source;

/** [owner] */
typedef struct ke_composition_source_handle
{
    ke_composition_source *ref;
    void (*destroy)(ke_composition_source *self);
} ke_composition_source_handle;

#ifdef __cplusplus
}
#endif

#endif
