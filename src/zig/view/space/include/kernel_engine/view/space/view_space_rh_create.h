#ifndef KERNEL_ENGINE_VIEW_SPACE_VIEW_SPACE_RH_CREATE_H_
#define KERNEL_ENGINE_VIEW_SPACE_VIEW_SPACE_RH_CREATE_H_

#include <kernel_engine/view/view_space.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C"
{
#endif

#if defined(_WIN32) && defined(KE_VIEW_SPACE_EXPORT)
#define KE_VIEW_SPACE_API __declspec(dllexport)
#elif defined(_WIN32)
#define KE_VIEW_SPACE_API __declspec(dllimport)
#else
#define KE_VIEW_SPACE_API
#endif

    /**
     * Right-handed view space: the camera looks down -z. A visible point has
     * negative view-space z, and the farther of two is the more negative.
     * @param out_view_space [out] Receives the view space; left zeroed on failure.
     * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p out_view_space, or
     *         KE_RESULT_OUT_OF_MEMORY.
     */
    KE_VIEW_SPACE_API ke_result
    ke_view_space_rh_create(ke_view_space_handle *out_view_space);

#ifdef __cplusplus
}
#endif

#endif
