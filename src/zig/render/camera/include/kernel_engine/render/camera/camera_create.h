#ifndef KERNEL_ENGINE_RENDER_CAMERA_CAMERA_CREATE_H_
#define KERNEL_ENGINE_RENDER_CAMERA_CAMERA_CREATE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/view/view_space.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_RENDER_CAMERA_API
#  ifdef KE_RENDER_CAMERA_EXPORT
#    define KE_RENDER_CAMERA_API KE_EXPORT
#  else
#    define KE_RENDER_CAMERA_API KE_IMPORT
#  endif
#endif

/**
 * Creates the camera interface over a view space and a clip convention.
 * @param view_space [borrowed] Must outlive the camera.
 * @param clip [borrowed] The device's clip conventions; copied.
 * @param out_error [out,optional] Set when construction fails.
 */
KE_RENDER_CAMERA_API ke_render_camera_handle ke_render_camera_create(
    ke_view_space *view_space, const ke_ndc_convention *clip, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
