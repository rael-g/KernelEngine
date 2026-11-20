#ifndef KERNEL_ENGINE_ASSEMBLY_TOML_ASSEMBLY_TOML_CREATE_H_
#define KERNEL_ENGINE_ASSEMBLY_TOML_ASSEMBLY_TOML_CREATE_H_

#include <kernel_engine/assembly/composition_source.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/file_system/file_system.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_ASSEMBLY_TOML_API
#  ifdef KE_ASSEMBLY_TOML_EXPORT
#    define KE_ASSEMBLY_TOML_API KE_EXPORT
#  else
#    define KE_ASSEMBLY_TOML_API KE_IMPORT
#  endif
#endif

/**
 * Creates a composition source that reads a TOML file through @p file_system, synchronously. Each table
 * `[instance.<name>]` adds the instance `<name>` of the part its `part` names, with the section its optional
 * `section` names; its optional table `bind` binds each slot it names to the instance a string names, or to each
 * instance an array names, in order; its optional array `order` orders each instance it names before the next,
 * across the instance's slots. Each key of the table `[defaults]` names a contract, whose default is the instance
 * its string names. Instances are added in the order the file declares them, then bindings, orders and defaults.
 * @param file_system [borrowed] The file system it reads through; must outlive the source.
 * @param out_source [out] Receives the source; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p file_system or @p out_source; KE_RESULT_OUT_OF_MEMORY.
 */
KE_ASSEMBLY_TOML_API ke_result ke_assembly_toml_create(ke_file_system *file_system,
                                                       ke_composition_source_handle *out_source);

#ifdef __cplusplus
}
#endif

#endif
