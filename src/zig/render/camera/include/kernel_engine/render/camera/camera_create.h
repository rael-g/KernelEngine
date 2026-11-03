#ifndef KERNEL_ENGINE_RENDER_CAMERA_CAMERA_CREATE_H_
#define KERNEL_ENGINE_RENDER_CAMERA_CAMERA_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/render/gpu/gpu_device.h>
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
 * Creates the camera interface over a view space and the clip convention of a device.
 * @param view_space [borrowed] Must outlive the camera.
 * @param device [borrowed] Read once, for its clip convention.
 * @param out_camera [out] Receives the handle; left zeroed on failure.
 */
KE_RENDER_CAMERA_API ke_result ke_render_camera_create(
    ke_view_space *view_space, ke_gpu_device *device, ke_render_camera_handle *out_camera);

#ifdef __cplusplus
}
#endif

#endif
