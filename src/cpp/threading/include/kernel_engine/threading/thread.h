#pragma once

#include <kernel_engine/kernel/threading/thread.h>
#include <kernel_engine/threading/threading_export.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Creates and immediately starts a new thread, filling the ke_thread vtable.
    KE_THREADING_API ke_result ke_thread_std_create(ke_allocator        *alloc,
                                                     const ke_thread_desc *desc,
                                                     ke_thread           **out);

    /// @brief Sets the name of the calling thread (useful for the main thread).
    KE_THREADING_API void ke_thread_set_current_name(const char *name);

    /// @brief Retrieves the name assigned to the calling thread.
    KE_THREADING_API const char* ke_thread_get_current_name(void);

    /// @brief Asserts that the calling thread matches the expected name.
    KE_THREADING_API void ke_thread_assert_current(const char *expected_name);

#ifdef __cplusplus
}
#endif
