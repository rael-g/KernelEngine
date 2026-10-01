#ifndef KERNEL_ENGINE_RENDER_CAMERA_H_
#define KERNEL_ENGINE_RENDER_CAMERA_H_

#include <kernel_engine/math/math.h>
#include <kernel_engine/render/components.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** The perspective frustum a camera's field of view describes. */
    typedef struct ke_camera_frustum
    {
        /// Tangent of half the vertical field of view.
        float tan_half_fov_y;
        float aspect;
        float near_plane;
        float far_plane;
    } ke_camera_frustum;

    /**
     * What a camera component and its world transform mean as matrices. Every
     * pass that draws from a camera asks this interface instead of working the
     * matrices out for itself, so all of them see the same camera.
     *
     * Every slot is callable at any time and tolerates a null `self`, a null
     * input or a null output by writing nothing.
     */
    typedef struct ke_render_camera
    {
        void *handle;

        /**
         * World-to-view for a camera placed by `camera_world`.
         * @param camera_world [borrowed] The camera's world transform.
         * @param out_view [out] Receives the view matrix.
         */
        void (*view)(struct ke_render_camera *self,
                     const ke_mat4           *camera_world,
                     ke_mat4                 *out_view);

        /**
         * The same view with its translation removed, for what is drawn
         * infinitely far away and so must not shift as the camera moves.
         * @param camera_world [borrowed] The camera's world transform.
         * @param out_view [out] Receives the view matrix.
         */
        void (*view_rotation)(struct ke_render_camera *self,
                              const ke_mat4           *camera_world,
                              ke_mat4                 *out_view);

        /**
         * The projection the camera describes. `orthographic` picks the kind,
         * `orthographic_size` is half the visible height, and `fov` is the
         * vertical field of view in degrees.
         * @param camera [borrowed] The camera component.
         * @param aspect Width over height of the surface drawn into.
         * @param out_proj [out] Receives the projection matrix.
         */
        void (*projection)(struct ke_render_camera    *self,
                           const ke_camera_component  *camera,
                           float                       aspect,
                           ke_mat4                    *out_proj);

        /**
         * A perspective projection from the camera's field of view, whatever
         * its `orthographic` flag says.
         * @param camera [borrowed] The camera component.
         * @param aspect Width over height of the surface drawn into.
         * @param out_proj [out] Receives the projection matrix.
         */
        void (*perspective_projection)(struct ke_render_camera   *self,
                                       const ke_camera_component *camera,
                                       float                      aspect,
                                       ke_mat4                   *out_proj);

        /**
         * The perspective frustum the camera's field of view describes,
         * whatever its `orthographic` flag says.
         * @param camera [borrowed] The camera component.
         * @param aspect Width over height of the surface drawn into.
         * @param out_frustum [out] Receives the frustum.
         */
        void (*perspective_frustum)(struct ke_render_camera   *self,
                                    const ke_camera_component *camera,
                                    float                      aspect,
                                    ke_camera_frustum         *out_frustum);
    } ke_render_camera;

    /** Owning wrapper: `ref` borrows for the lifetime, `destroy` ends it. */
    typedef struct ke_render_camera_handle
    {
        ke_render_camera *ref;
        void (*destroy)(ke_render_camera *self);
    } ke_render_camera_handle;

#ifdef __cplusplus
}
#endif

#endif
