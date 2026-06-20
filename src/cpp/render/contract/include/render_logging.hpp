#pragma once

#include <kernel_engine/logger/logger.h>
#include <kernel_engine/common/error.h>
#include <cstdio>

namespace kernel_engine::render
{

/**
 * @brief Helper to log an error and return false.
 */
inline bool LogErr(ke_logger *logger, bool /*unused*/, const char *tag, const char *context, const char *detail)
{
    if (logger)
    {
        char msg[1024];
        std::snprintf(msg, sizeof(msg), "%s: %s", context, detail);
        ke_log_event ev = {(int)KE_LOG_LEVEL_ERROR, tag, msg};
        logger->log(logger, &ev);
    }
    return false;
}

#define KE_RENDER_LOG_ERR(logger, res, context, detail) \
    ::kernel_engine::render::LogErr(logger, res, "render", context, detail)

} // namespace kernel_engine::render
