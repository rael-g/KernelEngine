#ifndef KERNEL_ENGINE_KERNEL_RENDER_RENDER_H_
#define KERNEL_ENGINE_KERNEL_RENDER_RENDER_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/render/light.h>
#include <kernel_engine/kernel/render/material.h>
#include <kernel_engine/kernel/render/mesh.h>
#include <kernel_engine/kernel/render/texture.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_RENDER "ke_render"

    /// @brief Opaque handle to a depth-buffer shadow map and its associated framebuffer.
    typedef uint32_t ke_shadow_map_handle;
#define KE_INVALID_SHADOW_MAP_HANDLE UINT32_MAX

    /// @brief Public interface for rendering operations.
    typedef struct ke_render
    {
        void *handle;
        void (*destroy)(struct ke_render *self);

        ke_result (*on_initialize)(struct ke_render *self);
        ke_result (*on_shutdown)(struct ke_render *self);

        ke_result (*set_orthographic)(struct ke_render *self, bool enabled);
        ke_result (*clear_color)(struct ke_render *self, float r, float g, float b, float a);

        ke_result (*frame)(struct ke_render *self);
        ke_result (*set_view_transform)(struct ke_render *self, const ke_mat4 *view, const ke_mat4 *proj);

        ke_result (*create_mesh)(struct ke_render *self,
                                 const ke_vertex *vertices, uint32_t vertex_count,
                                 const uint16_t *indices, uint32_t index_count,
                                 ke_mesh_handle *out_handle);

        ke_result (*destroy_mesh)(struct ke_render *self, ke_mesh_handle handle);

        ke_result (*create_material)(struct ke_render *self,
                                     const ke_material *mat,
                                     ke_material_handle *out_handle);

        ke_result (*destroy_material)(struct ke_render *self, ke_material_handle handle);

        ke_result (*submit_mesh)(struct ke_render *self,
                                 ke_mesh_handle mesh, ke_material_handle material,
                                 const ke_mat4 *transform);

        ke_result (*create_texture_rgba)(struct ke_render *self,
                                         uint32_t width, uint32_t height,
                                         const uint8_t *pixels,
                                         ke_texture_handle *out_handle);

        ke_result (*destroy_texture)(struct ke_render *self, ke_texture_handle handle);

        ke_result (*set_directional_light)(struct ke_render *self, const ke_directional_light *light);
        ke_result (*set_ambient_light)(struct ke_render *self, float r, float g, float b);
        ke_result (*set_camera_pos)(struct ke_render *self, float x, float y, float z);

        ke_result (*create_cubemap_rgba)(struct ke_render *self,
                                         uint32_t size,
                                         const uint8_t *data,
                                         ke_texture_handle *out_handle);

        ke_result (*submit_skybox)(struct ke_render *self, ke_texture_handle cubemap_handle);

        ke_result (*create_shadow_map)(struct ke_render *self, uint32_t width, uint32_t height,
                                       ke_shadow_map_handle *out_handle);

        ke_result (*destroy_shadow_map)(struct ke_render *self, ke_shadow_map_handle handle);

        ke_result (*begin_shadow_pass)(struct ke_render *self, ke_shadow_map_handle handle,
                                      const ke_mat4 *light_view, const ke_mat4 *light_proj);

        ke_result (*submit_mesh_shadow)(struct ke_render *self, ke_mesh_handle mesh,
                                        const ke_mat4 *transform);

        ke_result (*end_shadow_pass)(struct ke_render *self);

        ke_result (*set_shadow_map)(struct ke_render *self, ke_shadow_map_handle handle);

        /// @brief Enables HDR tonemapping. When enabled, the scene renders to an offscreen
        ///        RGBA16F framebuffer and the final output goes through ACES tonemapping.
        ke_result (*set_tonemapping)(struct ke_render *self, bool enabled,
                                     float exposure, float gamma);

        /// @brief Enables bloom post-processing. Requires tonemapping to be enabled first.
        ke_result (*set_bloom)(struct ke_render *self, bool enabled,
                               float threshold, float intensity);

        /// @brief Uploads an array of point lights for the current frame (max 8).
        ///        Replaces any previously set point lights.
        ke_result (*set_point_lights)(struct ke_render *self,
                                      const ke_point_light *lights, uint32_t count);

        /// @brief Uploads an array of spot lights for the current frame (max 8).
        ///        Replaces any previously set spot lights.
        ke_result (*set_spot_lights)(struct ke_render *self,
                                     const ke_spot_light *lights, uint32_t count);

    } ke_render;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_RENDER_RENDER_H_
