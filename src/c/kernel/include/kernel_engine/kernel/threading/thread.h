#ifndef KERNEL_ENGINE_KERNEL_THREADING_THREAD_H_
#define KERNEL_ENGINE_KERNEL_THREADING_THREAD_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/dev_platform/dev_platform.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Function signature for a thread entry point.
    typedef void (*ke_thread_func)(void *user_data);

    /// @brief Construction parameters for a thread factory.
    typedef struct ke_thread_params
    {
        const char       *name;         ///< Thread name. Stored in TLS and forwarded to dev_platform if present. May be NULL.
        ke_thread_func    func;         ///< Entry point. Must not be NULL.
        void             *user_data;    ///< Forwarded unchanged to func.
        ke_dev_platform  *dev_platform; ///< Optional. If set, used to make the thread name visible to debuggers/profilers.
    } ke_thread_params;

    /// @brief OS thread abstraction — vtable style.
    typedef struct ke_thread
    {
        void *handle;
        void (*destroy)(struct ke_thread *self, ke_allocator *alloc);
        void (*join)(struct ke_thread *self);

        /**
         * @brief Blocks until the thread finishes or the timeout expires.
         * @return true if the thread finished, false if it timed out.
         */
        ke_bool (*join_timeout)(struct ke_thread *self, uint32_t timeout_ms);
    } ke_thread;

    // Thread-name TLS helpers (`ke_thread_set_current_name`, `ke_thread_get_current_name`,
    // `ke_thread_assert_current`) live in `<kernel_engine/kernel/dev_platform/dev_platform.h>`
    // — they are dev-time facilities, not core threading primitives. This header transitively
    // pulls them in so existing consumers continue to compile without extra includes.

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_THREADING_THREAD_H_
