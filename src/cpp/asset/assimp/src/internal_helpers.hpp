#pragma once

#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/logger/logger.h>
#include <algorithm>
#include <cstring>
#include <cstdio>

namespace kernel_engine::asset::assimp::detail
{

inline void log_info(ke_logger *logger, const char *msg)
{
    if (!logger) return;
    ke_log_event ev = {KE_LOG_LEVEL_INFO, "asset_loader", msg};
    logger->log(logger, &ev);
}

inline void log_warn(ke_logger *logger, const char *msg)
{
    if (!logger) return;
    ke_log_event ev = {KE_LOG_LEVEL_WARNING, "asset_loader", msg};
    logger->log(logger, &ev);
}

inline void log_error(ke_logger *logger, const char *msg)
{
    if (!logger) return;
    ke_log_event ev = {KE_LOG_LEVEL_ERROR, "asset_loader", msg};
    logger->log(logger, &ev);
}

inline bool LogErr(ke_logger *logger, bool r, const char *context, const char *detail)
{
    if (logger)
    {
        char msg[1024];
        snprintf(msg, sizeof(msg), "%s: %s", context, detail);
        ke_log_event ev = {KE_LOG_LEVEL_ERROR, "asset_loader", msg};
        logger->log(logger, &ev);
    }
    return r;
}

/**
 * @brief Safely copies a string into a fixed-size buffer.
 * Does not trigger CRT secure warnings.
 */
inline void copy_string(char* dest, size_t dest_size, const char* src)
{
    if (!dest || dest_size == 0) return;
    if (!src)
    {
        dest[0] = '\0';
        return;
    }

    size_t src_len = std::strlen(src);
    size_t to_copy = std::min(src_len, dest_size - 1);
    std::copy(src, src + to_copy, dest);
    dest[to_copy] = '\0';
}

} // namespace kernel_engine::asset::assimp::detail
