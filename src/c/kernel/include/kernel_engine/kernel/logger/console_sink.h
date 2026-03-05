#ifndef KERNEL_ENGINE_KERNEL_LOGGER_CONSOLE_SINK_H_
#define KERNEL_ENGINE_KERNEL_LOGGER_CONSOLE_SINK_H_

#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/logger/log_level.h>
#include <kernel_engine/kernel/logger/logger.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Creates a sink that writes formatted log events to stderr.
    /// @param min_level Minimum level to print; events below this level are silently dropped.
    /// @return A value-type sink ready to pass to ke_logger::add_sink. No heap allocation is performed.
    KE_API ke_logger_sink ke_console_sink_create(ke_log_level min_level);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_LOGGER_CONSOLE_SINK_H_
