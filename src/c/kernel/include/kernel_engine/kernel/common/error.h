#ifndef KERNEL_ENGINE_KERNEL_COMMON_ERROR_H_
#define KERNEL_ENGINE_KERNEL_COMMON_ERROR_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Standard result codes for KernelEngine operations.
    typedef enum ke_result
    {
        KE_OK = 0,

        // Generic Errors
        KE_ERROR = 1,
        KE_ERROR_OUT_OF_MEMORY = 2,
        KE_ERROR_INVALID_ARGUMENT = 3,
        KE_ERROR_NOT_FOUND = 4,
        KE_ERROR_ALREADY_EXISTS = 5,
        KE_ERROR_NOT_INITIALIZED = 6,
        KE_ERROR_NOT_SUPPORTED = 7,

        // Domain Specific Errors
        KE_ERROR_IO = 100,
        KE_ERROR_WINDOW = 200,
        KE_ERROR_RENDER = 300,
        KE_ERROR_GPU_FATAL = 301,

    } ke_result;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_COMMON_ERROR_H_
