#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Diagnostic message severity levels.
    typedef enum ke_log_level
    {
        KE_LOG_LEVEL_TRACE = 0,
        KE_LOG_LEVEL_DEBUG = 1,
        KE_LOG_LEVEL_INFO = 2,
        KE_LOG_LEVEL_WARNING = 3,
        KE_LOG_LEVEL_ERROR = 4,
        KE_LOG_LEVEL_CRITICAL = 5
    } ke_log_level;

#ifdef __cplusplus
}
#endif
