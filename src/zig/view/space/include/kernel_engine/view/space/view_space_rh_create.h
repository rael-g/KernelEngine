#ifndef KERNEL_ENGINE_VIEW_SPACE_VIEW_SPACE_RH_CREATE_H_
#define KERNEL_ENGINE_VIEW_SPACE_VIEW_SPACE_RH_CREATE_H_

#include <kernel_engine/view/view_space.h>

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
     * @param out_error [out,optional] Set when construction fails.
     */
    KE_VIEW_SPACE_API ke_view_space_handle
    ke_view_space_rh_create(ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
