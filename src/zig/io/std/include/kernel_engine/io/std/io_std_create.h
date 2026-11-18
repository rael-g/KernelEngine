#ifndef KERNEL_ENGINE_IO_STD_IO_STD_CREATE_H_
#define KERNEL_ENGINE_IO_STD_IO_STD_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/file_system/file_system.h>
#include <kernel_engine/io/io.h>
#include <kernel_engine/settings/settings.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_IO_STD_API
#  ifdef KE_IO_STD_EXPORT
#    define KE_IO_STD_API KE_EXPORT
#  else
#    define KE_IO_STD_API KE_IMPORT
#  endif
#endif

/**
 * Creates a ke_io that runs each request on a pool of threads of its own, the thread pool of
 * Zig's `std.Io.Threaded`, reading through @p file_system.
 * @param file_system [borrowed] The file system each request reads through; borrowed for the
 *        lifetime of the ke_io.
 * @param settings [borrowed] Read once. "worker_count", the threads of the pool, default 2, at
 *        least 1; "stack_size", the bytes of each thread's stack, default 16 MiB; "submit_capacity",
 *        the requests that may wait for a thread, default 1024.
 * @param out_io [out] Receives the ke_io; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p file_system, @p settings or @p out_io, or
 *         a setting unknown, of another type or out of range; KE_RESULT_OUT_OF_MEMORY.
 */
KE_IO_STD_API ke_result ke_io_std_create(ke_file_system *file_system, ke_settings *settings, ke_io_handle *out_io);

#ifdef __cplusplus
}
#endif

#endif
