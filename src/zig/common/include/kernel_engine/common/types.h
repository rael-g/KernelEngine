#ifndef KERNEL_ENGINE_COMMON_TYPES_H_
#define KERNEL_ENGINE_COMMON_TYPES_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief ABI-stable boolean type. Use in vtable slots and struct fields that cross the C ABI
    ///        boundary, in place of plain C `bool`.
    typedef uint8_t ke_bool;

#ifdef __cplusplus
}
#endif

#endif
