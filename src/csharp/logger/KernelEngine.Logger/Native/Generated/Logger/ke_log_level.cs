using KernelEngine.Common.Native;

namespace KernelEngine.Logger.Native;

public enum ke_log_level
{
    KE_LOG_LEVEL_TRACE = 0,
    KE_LOG_LEVEL_DEBUG = 1,
    KE_LOG_LEVEL_INFO = 2,
    KE_LOG_LEVEL_WARNING = 3,
    KE_LOG_LEVEL_ERROR = 4,
    KE_LOG_LEVEL_CRITICAL = 5,
}
