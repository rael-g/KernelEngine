#ifndef KERNEL_ENGINE_FRAMEWORK_ASSET_RESOLVER_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_ASSET_RESOLVER_CREATE_H_

#include <kernel_engine/kernel/asset/asset_resolver.h>

#ifdef __cplusplus
extern "C"
{
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
