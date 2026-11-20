#ifndef KERNEL_ENGINE_ASYNC_INLINE_ASYNC_INLINE_PARTS_H_
#define KERNEL_ENGINE_ASYNC_INLINE_ASYNC_INLINE_PARTS_H_

#include <kernel_engine/async/inline/async_inline_create.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_async_inline contains: `async_inline`, providing ke_async.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_ASYNC_INLINE_CREATE_API const ke_part *ke_async_inline_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
