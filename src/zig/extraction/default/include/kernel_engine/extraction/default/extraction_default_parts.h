#ifndef KERNEL_ENGINE_EXTRACTION_DEFAULT_EXTRACTION_DEFAULT_PARTS_H_
#define KERNEL_ENGINE_EXTRACTION_DEFAULT_EXTRACTION_DEFAULT_PARTS_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_EXTRACTION_DEFAULT_API
#  ifdef KE_EXTRACTION_DEFAULT_EXPORT
#    define KE_EXTRACTION_DEFAULT_API KE_EXPORT
#  else
#    define KE_EXTRACTION_DEFAULT_API KE_IMPORT
#  endif
#endif

/**
 * Gives the parts ke_extraction_default contains: `extraction`, providing ke_extraction and ke_scheduler_executable, with the slots `main`, `render`, `scheduler` and `render_schedule`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_EXTRACTION_DEFAULT_API const ke_part *ke_extraction_default_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
