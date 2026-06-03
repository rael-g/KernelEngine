#ifndef KERNEL_ENGINE_KERNEL_COMMON_THREAD_NAME_H_
#define KERNEL_ENGINE_KERNEL_COMMON_THREAD_NAME_H_

#include <kernel_engine/kernel/context/types.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // ── Cross-language thread-name TLS ───────────────────────────────────────
    //
    // Every thread carries a string label in TLS (default "unknown"). The label
    // is set by whichever language spawns the thread (C#, C++, Rust, ...) and
    // is consumed by kernel + plugin code for thread-affinity assertions.
    //
    // These functions are kernel-level identity primitives, not dev-tools — a
    // bgfx plugin running on ke.render thread asserts via ke_thread_assert_current
    // regardless of whether the host is C# or anything else. They were previously
    // co-located with ke_dev_platform but live here now because OS-visible
    // thread naming is no longer a dedicated contract (managed runtimes propagate
    // their own Thread.Name to the OS).

    /**
     * @brief Sets the kernel-side TLS name of the calling thread.
     * @note Truncates to an internal 64-byte buffer.
     */
    KE_API void ke_thread_set_current_name(const char *name);

    /// @brief Returns the TLS name of the calling thread (or "unknown" if never set).
    KE_API const char *ke_thread_get_current_name(void);

    /**
     * @brief Aborts in debug builds when the calling thread's TLS name does not
     *        match @p expected_name. No-op in release.
     */
    KE_API void ke_thread_assert_current(const char *expected_name);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_COMMON_THREAD_NAME_H_
