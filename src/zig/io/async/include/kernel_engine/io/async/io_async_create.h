#ifndef KERNEL_ENGINE_IO_ASYNC_IO_ASYNC_CREATE_H_
#define KERNEL_ENGINE_IO_ASYNC_IO_ASYNC_CREATE_H_

#include <kernel_engine/async/async.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/file_system/file_system.h>
#include <kernel_engine/io/io.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_IO_ASYNC_API
#  ifdef KE_IO_ASYNC_EXPORT
#    define KE_IO_ASYNC_API KE_EXPORT
#  else
#    define KE_IO_ASYNC_API KE_IMPORT
#  endif
#endif

/**
 * Creates a ke_io that runs each request as one operation of @p async, reading through
 * @p file_system.
 * @param async [borrowed] The system each request runs on; borrowed for the lifetime of the ke_io.
 * @param file_system [borrowed] The file system each request reads through; borrowed for the
 *        lifetime of the ke_io.
 * @param out_io [out] Receives the ke_io; left zeroed on failure.
 * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p async, @p file_system or @p out_io,
 *         or KE_RESULT_OUT_OF_MEMORY.
 */
KE_IO_ASYNC_API ke_result ke_io_async_create(ke_async *async, ke_file_system *file_system, ke_io_handle *out_io);

#ifdef __cplusplus
}
#endif

#endif
