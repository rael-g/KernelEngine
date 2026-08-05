#ifndef KERNEL_ENGINE_FRAMEWORK_NODE_HOST_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_NODE_HOST_CREATE_H_

#include <kernel_engine/framework/node_host.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/runtime/runtime.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_FRAMEWORK_API
#if defined(_WIN32) || defined(__CYGWIN__)
#ifdef KE_FRAMEWORK_STATIC
#define KE_FRAMEWORK_API
#else
#ifdef KE_FRAMEWORK_EXPORT
#define KE_FRAMEWORK_API __declspec(dllexport)
#else
#define KE_FRAMEWORK_API __declspec(dllimport)
#endif
#endif
#else
#define KE_FRAMEWORK_API __attribute__((visibility("default")))
#endif
#endif

    /// Creates a node host backed by the supplied ecs + runtime (both borrowed,
    /// must outlive the host). Caller invokes host->destroy(host) when done.
    KE_FRAMEWORK_API ke_node_host_handle ke_node_host_create(
        ke_ecs     *ecs,
        ke_runtime *runtime,
        ke_error  **out_error);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_NODE_HOST_CREATE_H_
