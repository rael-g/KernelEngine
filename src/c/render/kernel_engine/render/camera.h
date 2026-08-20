#ifndef KERNEL_ENGINE_RENDER_CAMERA_H_
#define KERNEL_ENGINE_RENDER_CAMERA_H_

#include <kernel_engine/common/math.h>
#include <kernel_engine/render/components.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/view/view_space.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /**
     * The projection a camera component describes, built in `view_space` for
     * `clip`. Reads `orthographic` to pick the kind, `orthographic_size` as half
     * the visible height, and `fov` as the vertical field of view in degrees.
     * @param out_proj [out] Receives the projection matrix.
     */
    static inline void ke_camera_projection(const ke_camera_component *cam,
                                            float                      aspect,
                                            ke_view_space             *view_space,
                                            const ke_ndc_convention   *clip,
                                            ke_mat4                   *out_proj)
    {
        if (cam == NULL || view_space == NULL || clip == NULL || out_proj == NULL) { return; }

        if (cam->orthographic != 0)
        {
            const float height = cam->orthographic_size * 2.0f;
            view_space->orthographic(view_space, height * aspect, height,
                                     cam->near_plane, cam->far_plane, clip, out_proj);
            return;
        }

        const float fov_y = cam->fov * 0.017453292519943295f;
        view_space->perspective(view_space, fov_y, aspect,
                                cam->near_plane, cam->far_plane, clip, out_proj);
    }

#ifdef __cplusplus
}
#endif

#endif
