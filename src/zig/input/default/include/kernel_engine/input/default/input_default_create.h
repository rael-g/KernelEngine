#ifndef KERNEL_ENGINE_INPUT_DEFAULT_INPUT_DEFAULT_CREATE_H_
#define KERNEL_ENGINE_INPUT_DEFAULT_INPUT_DEFAULT_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/input/input.h>

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

/** Creates an input system. */
KE_INPUT_DEFAULT_API ke_input_handle ke_input_create(ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
