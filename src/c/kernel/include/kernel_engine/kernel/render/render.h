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

    } ke_render;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_RENDER_RENDER_H_
