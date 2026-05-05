#ifndef KERNEL_ENGINE_KERNEL_THREADING_THREAD_H_
#define KERNEL_ENGINE_KERNEL_THREADING_THREAD_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Function signature for a thread entry point.
    typedef void (*ke_thread_func)(void *user_data);

    /// @brief Construction parameters for a thread factory.
    typedef struct ke_thread_desc
    {
        const char    *name;          ///< Thread name, visible in profilers. May be NULL.
        ke_thread_func func;          ///< Entry point. Must not be NULL.
        void          *user_data;     ///< Forwarded unchanged to func.
        uint64_t       affinity_mask; ///< CPU affinity bitmask. 0 = no preference.
    } ke_thread_desc;

    /// @brief OS thread abstraction — vtable style.
    typedef struct ke_thread
    {
        void *handle;
        void (*destroy)(struct ke_thread *self, ke_allocator *alloc);
        void (*join)(struct ke_thread *self);
    } ke_thread;

    /**
     * @brief Assigns a human-readable name to the calling thread.
     * Stored in TLS and visible in debuggers/profilers.
     */
    void ke_thread_set_current_name(const char *name);

    /**
     * @brief Retrieves the name assigned to the calling thread.
     * @return Thread name or "unknown" if never set.
     */
    const char* ke_thread_get_current_name(void);

    /**
     * @brief Asserts that the calling thread matches the expected name.
     * In debug builds, crashes with a diagnostic message if it fails.
     * No-op in release builds.
     */
    void ke_thread_assert_current(const char *expected_name);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_THREADING_THREAD_H_
