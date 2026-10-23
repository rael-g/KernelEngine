#ifndef KERNEL_ENGINE_FRAMEWORK_ASSET_RESOLVER_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_ASSET_RESOLVER_CREATE_H_

#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/asset/image_loader.h>
#include <kernel_engine/text/font.h>
#include <kernel_engine/result/result.h>

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

    /// Allocates a new resolver. Both loader pointers may be NULL — the
    /// corresponding resolve_* slot then returns KE_RESULT_INVALID_ARGUMENT.
    /// The resolver does NOT take ownership of either loader.
    /// @p project_root may be NULL — res:// resolution is
    /// then disabled; only absolute or CWD-relative paths work.
    /// @param out_resolver [out] Receives the resolver; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p out_resolver, or
    ///         KE_RESULT_OUT_OF_MEMORY.
    KE_FRAMEWORK_API ke_result ke_asset_resolver_create(
        ke_image_loader          *image_loader,
        ke_font_loader           *font_loader,
        const char               *project_root,
        ke_asset_resolver_handle *out_resolver);

#ifdef __cplusplus
}
#endif

#endif
