#ifndef KERNEL_ENGINE_FRAMEWORK_RENDER_ASSETS_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_RENDER_ASSETS_CREATE_H_

#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/render/assets.h>
#include <kernel_engine/render/service/render_service.h>
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

    /// Allocates render assets over a resolver and a render service, neither of which it owns.
    /// @param resolver [borrowed] What reads each asset; must outlive the render assets.
    /// @param service [borrowed] What holds what they make; must outlive the render assets.
    /// @param out_assets [out] Receives the render assets; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument, or KE_RESULT_OUT_OF_MEMORY.
    KE_FRAMEWORK_API ke_result ke_render_assets_create(
        ke_asset_resolver       *resolver,
        ke_render_service       *service,
        ke_render_assets_handle *out_assets);

#ifdef __cplusplus
}
#endif

#endif
