#ifndef KERNEL_ENGINE_LOGGER_SIMPLE_CONSOLE_SINK_CREATE_H_
#define KERNEL_ENGINE_LOGGER_SIMPLE_CONSOLE_SINK_CREATE_H_

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

/**
 * Builds a stateless sink that formats entries as `[LEVEL] tag: message`
 * and writes them to the process's standard error stream, flushing after
 * every entry. Every language wants this as a default; native so none of
 * them re-derive the format.
 */
KE_LOGGER_SIMPLE_API ke_logger_sink ke_console_sink_create(void);

#ifdef __cplusplus
}
#endif

#endif
