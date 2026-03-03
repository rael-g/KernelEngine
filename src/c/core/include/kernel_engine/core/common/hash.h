#pragma once

#include <kernel_engine/core/context/types.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Computes a 64-bit hash for a string.
    KE_API uint64_t ke_hash_string(const char *str);

#ifdef __cplusplus
}
#endif
