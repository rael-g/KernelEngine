#ifndef KERNEL_ENGINE_IO_INLINE_IO_INLINE_CREATE_H_
#define KERNEL_ENGINE_IO_INLINE_IO_INLINE_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/file_system/file_system.h>
#include <kernel_engine/io/io.h>
#include <kernel_engine/settings/settings.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_IO_INLINE_API
#  ifdef KE_IO_INLINE_EXPORT
#    define KE_IO_INLINE_API KE_EXPORT
#  else
#    define KE_IO_INLINE_API KE_IMPORT
#  endif
#endif

/**
 * Creates a ke_io with no thread of its own: each request runs on the calling thread, through
 * @p file_system, before the call that submits it returns, so its completion has already finished.
 * @param file_system [borrowed] The file system each request reads through; borrowed for the
 *        lifetime of the ke_io.
 * @param settings [borrowed] Read once; this implementation has no setting of its own.
 * @param out_io [out] Receives the ke_io; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p file_system, @p settings or @p out_io, or
 *         any setting; KE_RESULT_OUT_OF_MEMORY.
 */
KE_IO_INLINE_API ke_result ke_io_inline_create(ke_file_system *file_system, ke_settings *settings, ke_io_handle *out_io);

#ifdef __cplusplus
}
#endif

#endif
