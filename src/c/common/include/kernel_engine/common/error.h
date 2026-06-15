#ifndef KERNEL_ENGINE_COMMON_ERROR_H_
#define KERNEL_ENGINE_COMMON_ERROR_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

/// @brief Signed 32-bit result code. KE_OK (0) = success; negative = error.
/// Domain-specific codes are defined in each domain's own header.
typedef int32_t ke_result;

#define KE_OK                      ((ke_result) 0)
#define KE_ERROR                   ((ke_result)-1)
#define KE_ERROR_OUT_OF_MEMORY     ((ke_result)-2)
#define KE_ERROR_INVALID_ARGUMENT  ((ke_result)-3)
#define KE_ERROR_NOT_FOUND         ((ke_result)-4)
#define KE_ERROR_NOT_INITIALIZED   ((ke_result)-5)
#define KE_ERROR_NOT_SUPPORTED     ((ke_result)-6)
#define KE_ERROR_ALREADY_EXISTS    ((ke_result)-7)
#define KE_ERROR_IO                ((ke_result)-8)

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_COMMON_ERROR_H_
