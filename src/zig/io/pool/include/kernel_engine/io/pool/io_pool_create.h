#ifndef KERNEL_ENGINE_IO_POOL_IO_POOL_CREATE_H_
#define KERNEL_ENGINE_IO_POOL_IO_POOL_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/file_system/file_system.h>
#include <kernel_engine/io/io.h>
#include <kernel_engine/task_pool/task_pool.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_IO_POOL_API
#  ifdef KE_IO_POOL_EXPORT
#    define KE_IO_POOL_API KE_EXPORT
#  else
#    define KE_IO_POOL_API KE_IMPORT
#  endif
#endif

/** Construction parameters for ke_io_pool_create. */
typedef struct ke_io_pool_params
{
    /// [provider] The pool each request runs on; required, borrowed for the lifetime of the ke_io.
    ke_task_pool *task_pool;
    /// [provider] The file system each request reads through; required, borrowed for the lifetime
    /// of the ke_io.
    ke_file_system *file_system;
} ke_io_pool_params;

/**
 * Creates a ke_io that runs each request as one task of @p params' task pool, reading through its
 * file system.
 * @param params [borrowed] The task pool and the file system.
 * @param out_io [out] Receives the ke_io; left zeroed on failure.
 * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p params, task pool, file system or
 *         @p out_io, or KE_RESULT_OUT_OF_MEMORY.
 */
KE_IO_POOL_API ke_result ke_io_pool_create(const ke_io_pool_params *params, ke_io_handle *out_io);

#ifdef __cplusplus
}
#endif

#endif
