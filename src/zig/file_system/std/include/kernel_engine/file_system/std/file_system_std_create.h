#ifndef KERNEL_ENGINE_FILE_SYSTEM_STD_FILE_SYSTEM_STD_CREATE_H_
#define KERNEL_ENGINE_FILE_SYSTEM_STD_FILE_SYSTEM_STD_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/file_system/file_system.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_FILE_SYSTEM_STD_API
#  ifdef KE_FILE_SYSTEM_STD_EXPORT
#    define KE_FILE_SYSTEM_STD_API KE_EXPORT
#  else
#    define KE_FILE_SYSTEM_STD_API KE_IMPORT
#  endif
#endif

/** [bag] Construction parameters for ke_file_system_std_create. */
typedef struct ke_file_system_std_params
{
    /// [default:null] [utf8] The directory relative paths are resolved against; null takes the working
    /// directory of the process.
    const char *root;
} ke_file_system_std_params;

/**
 * Creates a ke_file_system over the operating system's files, through Zig's standard library.
 * @param params [borrowed,optional] Construction parameters; NULL takes every default.
 * @param out_file_system [out] Receives the file system; left zeroed on failure.
 * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p out_file_system, KE_RESULT_NOT_FOUND for a
 *         root that names no directory, KE_RESULT_OUT_OF_MEMORY, or KE_RESULT_IO.
 */
KE_FILE_SYSTEM_STD_API ke_result ke_file_system_std_create(const ke_file_system_std_params *params,
                                                           ke_file_system_handle           *out_file_system);

#ifdef __cplusplus
}
#endif

#endif
