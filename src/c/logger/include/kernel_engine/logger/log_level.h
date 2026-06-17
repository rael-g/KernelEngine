#ifndef KERNEL_ENGINE_LOGGER_LOG_LEVEL_H_
#define KERNEL_ENGINE_LOGGER_LOG_LEVEL_H_

#include <kernel_engine/logger/logger_export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Diagnostic message severity levels.
    typedef enum ke_log_level
    {
        KE_LOG_LEVEL_TRACE    = 0,
        KE_LOG_LEVEL_DEBUG    = 1,
        KE_LOG_LEVEL_INFO     = 2,
        KE_LOG_LEVEL_WARNING  = 3,
        KE_LOG_LEVEL_ERROR    = 4,
        KE_LOG_LEVEL_CRITICAL = 5,
    } ke_log_level;

    /// @brief Converts a log level to a human-readable string.
    KE_LOGGER_API const char *ke_log_level_to_string(int32_t level);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_LOGGER_LOG_LEVEL_H_
