#ifndef KERNEL_ENGINE_IO_STD_IO_STD_PARTS_H_
#define KERNEL_ENGINE_IO_STD_IO_STD_PARTS_H_

#include <kernel_engine/io/std/io_std_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_io_std contains: `io_std`, providing ke_io, with the slot `file_system`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_IO_STD_API const ke_part *ke_io_std_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
