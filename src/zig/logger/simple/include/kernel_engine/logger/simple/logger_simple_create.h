#ifndef KERNEL_ENGINE_LOGGER_SIMPLE_LOGGER_SIMPLE_CREATE_H_
#define KERNEL_ENGINE_LOGGER_SIMPLE_LOGGER_SIMPLE_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/logger/logger.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_LOGGER_SIMPLE_API
#  ifdef KE_LOGGER_SIMPLE_EXPORT
#    define KE_LOGGER_SIMPLE_API KE_EXPORT
#  else
#    define KE_LOGGER_SIMPLE_API KE_IMPORT
#  endif
#endif

/** Creates a logger instance. */
KE_LOGGER_SIMPLE_API ke_logger_handle ke_logger_create(ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
