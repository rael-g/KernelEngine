#pragma once

#include <kernel_engine/kernel/logger/logger.h>

namespace kernel_engine::window::glfw::detail
{

inline void glfw_log(ke_logger *logger, ke_log_level level, const char *msg)
{
    if (!logger || (int32_t)level < logger->runtime_limit) return;
    ke_log_event ev = {(int32_t)level, "glfw", msg};
    logger->log(logger, &ev);
}

} // namespace kernel_engine::window::glfw::detail
