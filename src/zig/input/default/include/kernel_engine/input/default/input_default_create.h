#ifndef KERNEL_ENGINE_INPUT_DEFAULT_INPUT_DEFAULT_CREATE_H_
#define KERNEL_ENGINE_INPUT_DEFAULT_INPUT_DEFAULT_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/input/input.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_INPUT_DEFAULT_API
#  ifdef KE_INPUT_DEFAULT_EXPORT
#    define KE_INPUT_DEFAULT_API KE_EXPORT
#  else
#    define KE_INPUT_DEFAULT_API KE_IMPORT
#  endif
#endif

/**
 * Creates an input system.
 * @param out_input [out] Receives the input system; left zeroed on failure.
 * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p out_input, or KE_RESULT_OUT_OF_MEMORY.
 */
KE_INPUT_DEFAULT_API ke_result ke_input_create(ke_input_handle *out_input);

#ifdef __cplusplus
}
#endif

#endif
