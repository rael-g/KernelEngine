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

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_DEV_PLATFORM_DEV_PLATFORM_H_
