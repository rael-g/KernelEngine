#ifndef KERNEL_ENGINE_FRAMEWORK_ASSET_RESOLVER_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_ASSET_RESOLVER_CREATE_H_

#include <kernel_engine/kernel/asset/asset_resolver.h>
#include <kernel_engine/kernel/asset/image_loader.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>

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

    /// Allocates a new resolver. <paramref name="image_loader"/> may be NULL
    /// (resolve_texture then returns KE_ERROR_INVALID_ARGUMENT). The resolver
    /// does NOT take ownership of the injected loader.
    /// <paramref name="project_root"/> may also be NULL — res:// resolution
    /// is then disabled, and only absolute or CWD-relative paths work.
    KE_FRAMEWORK_API ke_result ke_asset_resolver_create(
        ke_allocator       *alloc,
        ke_image_loader    *image_loader,
        const char         *project_root,
        ke_asset_resolver **out);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_ASSET_RESOLVER_CREATE_H_
