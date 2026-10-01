#ifndef KERNEL_ENGINE_VIEW_VIEW_SPACE_H_
#define KERNEL_ENGINE_VIEW_VIEW_SPACE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/math/math.h>
#include <kernel_engine/render/gpu/ndc_convention.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** The view space as plain data, for consumers that cannot call this interface. */
    typedef struct ke_view_space_params
    {
        /// Multiplies a view-space z into a distance in front of the camera.
        float depth_from_view_z;
    } ke_view_space_params;

    /**
     * How the engine lays out view space: which way the camera faces along z,
     * and with it the shape of the view and projection matrices. Independent of
     * `ke_ndc_convention`, which reports the clip space of the device.
     *
     * Every slot is callable at any time. No slot's result is documented as
     * constant; a consumer that caches one is making its own choice.
     */
    typedef struct ke_view_space
    {
        void *handle;

        /** The numbers to hand to consumers that cannot call this interface. */
        ke_view_space_params (*params)(struct ke_view_space *self);

        /**
         * World-to-view for a camera at `eye` facing `forward` with `up` above.
         * @param forward [borrowed] Need not be normalized.
         * @param out_view [out] Receives the view matrix.
         */
        void (*look_to)(struct ke_view_space *self,
                        const ke_vec3 *eye,
                        const ke_vec3 *forward,
                        const ke_vec3 *up,
                        ke_mat4       *out_view);

        /**
         * World-to-view for a camera at `eye` aimed at `target`.
         * @param out_view [out] Receives the view matrix.
         */
        void (*look_at)(struct ke_view_space *self,
                        const ke_vec3 *eye,
                        const ke_vec3 *target,
                        const ke_vec3 *up,
                        ke_mat4       *out_view);

        /**
         * World-to-view for a camera placed by `camera_world`, whose rotation
         * basis gives the camera's local axes. Which of them the camera faces
         * along is the view space's to decide, so the same transform yields
         * opposite facings under the two handednesses. A basis carrying no
         * rotation aims at the world origin.
         * @param camera_world [borrowed] The camera's world transform.
         * @param out_view [out] Receives the view matrix.
         */
        void (*view_from_transform)(struct ke_view_space *self,
                                    const ke_mat4        *camera_world,
                                    ke_mat4              *out_view);

        /**
         * Perspective projection into `clip`'s conventions.
         * @param fov_y Vertical field of view, in radians.
         * @param clip [borrowed] The device's clip space, from get_ndc_convention.
         * @param out_proj [out] Receives the projection matrix.
         */
        void (*perspective)(struct ke_view_space *self,
                            float                      fov_y,
                            float                      aspect,
                            float                      near_plane,
                            float                      far_plane,
                            const ke_ndc_convention   *clip,
                            ke_mat4                   *out_proj);

        /**
         * Orthographic projection into `clip`'s conventions.
         * @param clip [borrowed] The device's clip space, from get_ndc_convention.
         * @param out_proj [out] Receives the projection matrix.
         */
        void (*orthographic)(struct ke_view_space *self,
                             float                      width,
                             float                      height,
                             float                      near_plane,
                             float                      far_plane,
                             const ke_ndc_convention   *clip,
                             ke_mat4                   *out_proj);
    } ke_view_space;

    /** Owning wrapper: `ref` borrows for the lifetime, `destroy` ends it. */
    typedef struct ke_view_space_handle
    {
        ke_view_space *ref;
        void (*destroy)(ke_view_space *self);
    } ke_view_space_handle;

#ifdef __cplusplus
}
#endif

#endif
