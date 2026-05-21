#ifndef KERNEL_ENGINE_KERNEL_DEV_PLATFORM_DEV_PLATFORM_H_
#define KERNEL_ENGINE_KERNEL_DEV_PLATFORM_DEV_PLATFORM_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/types.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_DEV_PLATFORM "ke_dev_platform"

    /**
     * @brief Optional, dev-only platform abstraction.
     *
     * Hosts operations that:
     *   - have no cross-platform std/C++ equivalent,
     *   - are only useful in development/debug builds,
     *   - degrade gracefully to no-op when absent (shipped builds without dev tools).
     *
     * Examples: OS-visible thread naming (debugger/profiler), crash handler installation,
     * minidump writing, file change watching for hot-reload.
     *
     * NEVER add operations here that are required for the engine to function correctly
     * in a shipping build — those belong in the kernel proper.
     */
    typedef struct ke_dev_platform
    {
        void *handle;

        void (*destroy)(struct ke_dev_platform *self);

        /**
         * @brief Sets the OS-visible name of the calling thread.
         * Visible in debuggers and profilers (Visual Studio, perf, RenderDoc, etc.).
         * Implementation is best-effort — failure is silent and harmless.
         */
        void (*set_thread_name)(struct ke_dev_platform *self, const char *name);

    } ke_dev_platform;

    // ── Thread-name TLS helpers ──────────────────────────────────────────────
    // Each thread carries a string label in TLS (default "unknown"). The label is set
    // by `ke_thread_create` for spawned threads and by the application for the OS-given
    // main thread, and is consumed by `ke_thread_assert_current` for thread-affinity
    // checks. These functions live alongside `ke_dev_platform` because they exist
    // primarily for development/observability, not for shipping-build behavior.

    /**
     * @brief Sets the kernel-side TLS name of the calling thread.
     * Independent from `set_thread_name` on the vtable (which talks to the OS).
     */
    KE_API void ke_thread_set_current_name(const char *name);

    /// @brief Retrieves the TLS name of the calling thread, or "unknown" if never set.
    KE_API const char *ke_thread_get_current_name(void);

    /**
     * @brief Asserts that the calling thread's TLS name matches @p expected_name.
     * Aborts with a fatal message in debug builds; no-op in release.
     */
    KE_API void ke_thread_assert_current(const char *expected_name);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_DEV_PLATFORM_DEV_PLATFORM_H_
