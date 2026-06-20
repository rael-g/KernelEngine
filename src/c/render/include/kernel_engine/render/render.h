#ifndef KERNEL_ENGINE_RENDER_RENDER_H_
#define KERNEL_ENGINE_RENDER_RENDER_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/math.h>

#include <kernel_engine/render/handles.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/render/light.h>
#include <kernel_engine/render/material.h>
#include <kernel_engine/render/mesh.h>
#include <kernel_engine/render/texture.h>
#include <kernel_engine/common/types.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    struct ke_frame_packet;
    typedef struct ke_render_graph ke_render_graph;

    /// @brief Owner wrapper for a render graph (only pointers, so a forward decl suffices).
    /// Full graph definition + the ke_render_graph_create wrapper live in render_graph.h.
    typedef struct ke_render_graph_handle
    {
        ke_render_graph *ref;
        void (*destroy)(ke_render_graph *self);
    } ke_render_graph_handle;

#define KE_ID_RENDER "ke_render"

    /// @brief Clip-space (NDC) convention the active render backend expects matrices in.
    /// The engine's matrix builders query this and build accordingly, so the same game code
    /// produces correct projections across backends (Vulkan/D3D vs OpenGL, etc.).
    typedef struct ke_ndc_convention
    {
        ke_bool z_zero_to_one; ///< 1 = clip z in [0,1] (Vulkan/D3D), 0 = [-1,1] (OpenGL).
        ke_bool y_flip;        ///< 1 = framebuffer origin top-left needs Y flip in projection.
        ke_bool left_handed;   ///< 1 = left-handed clip space, 0 = right-handed.
    } ke_ndc_convention;

    /// @brief Configuration for the Clustered Forward Shading grid.
    typedef struct ke_cluster_config
    {
        uint32_t grid_x;
        uint32_t grid_y;
        uint32_t grid_z;
        uint32_t max_lights_per_cluster;
        uint32_t max_total_lights;
    } ke_cluster_config;

    /// @brief Public interface for rendering operations.
    typedef struct ke_render
    {
        void *handle;

        bool (*on_initialize)(struct ke_render *self, ke_error **out_error);
        bool (*on_shutdown)(struct ke_render *self, ke_error **out_error);

        bool (*set_orthographic)(struct ke_render *self, ke_bool enabled, ke_error **out_error);
        bool (*clear_color)(struct ke_render *self, float r, float g, float b, float a, ke_error **out_error);

        bool (*frame)(struct ke_render *self, ke_error **out_error);
        bool (*set_view_transform)(struct ke_render *self, const ke_mat4 *view, const ke_mat4 *proj, ke_error **out_error);

        /// @brief Returns the clip-space convention this backend expects matrices in.
        /// Valid after on_initialize. The engine's matrix builders use it so projections are correct per backend.
        ke_ndc_convention (*get_ndc_convention)(struct ke_render *self);

        ke_mesh_handle (*create_mesh)(struct ke_render *self,
                                      const ke_vertex *vertices, uint32_t vertex_count,
                                      const uint16_t *indices, uint32_t index_count,
                                      ke_error **out_error);

        bool (*destroy_mesh)(struct ke_render *self, ke_mesh_handle handle, ke_error **out_error);

        ke_material_handle (*create_material)(struct ke_render *self,
                                              const ke_material *mat,
                                              ke_error **out_error);

        bool (*destroy_material)(struct ke_render *self, ke_material_handle handle, ke_error **out_error);

        bool (*submit_mesh)(struct ke_render *self,
                            ke_mesh_handle mesh, ke_material_handle material,
                            const ke_mat4 *transform, ke_error **out_error);

        ke_texture_handle (*create_texture_rgba)(struct ke_render *self,
                                                 uint32_t width, uint32_t height,
                                                 const uint8_t *pixels,
                                                 ke_error **out_error);

        bool (*destroy_texture)(struct ke_render *self, ke_texture_handle handle, ke_error **out_error);

        bool (*set_directional_light)(struct ke_render *self, const ke_directional_light *light, ke_error **out_error);
        bool (*set_ambient_light)(struct ke_render *self, float r, float g, float b, ke_error **out_error);
        bool (*set_camera_pos)(struct ke_render *self, float x, float y, float z, ke_error **out_error);

        ke_texture_handle (*create_cubemap_rgba)(struct ke_render *self,
                                                 uint32_t size,
                                                 const uint8_t *data,
                                                 ke_error **out_error);

        bool (*submit_skybox)(struct ke_render *self, ke_texture_handle cubemap_handle, ke_error **out_error);

        ke_shadow_map_handle (*create_shadow_map)(struct ke_render *self, uint32_t width, uint32_t height,
                                                  ke_error **out_error);

        bool (*destroy_shadow_map)(struct ke_render *self, ke_shadow_map_handle handle, ke_error **out_error);

        bool (*begin_shadow_pass)(struct ke_render *self, ke_shadow_map_handle handle,
                                  const ke_mat4 *light_view, const ke_mat4 *light_proj, ke_error **out_error);

        bool (*submit_mesh_shadow)(struct ke_render *self, ke_mesh_handle mesh,
                                   const ke_mat4 *transform, ke_error **out_error);

        bool (*end_shadow_pass)(struct ke_render *self, ke_error **out_error);

        bool (*set_shadow_map)(struct ke_render *self, ke_shadow_map_handle handle, ke_error **out_error);

        /// @brief Enables HDR tonemapping. When enabled, the scene renders to an offscreen
        ///        RGBA16F framebuffer and the final output goes through ACES tonemapping.
        bool (*set_tonemapping)(struct ke_render *self, ke_bool enabled,
                                float exposure, float gamma, ke_error **out_error);

        /// @brief Enables bloom post-processing. Requires tonemapping to be enabled first.
        bool (*set_bloom)(struct ke_render *self, ke_bool enabled,
                          float threshold, float intensity, ke_error **out_error);

        /// @brief Uploads an array of point lights for the current frame.
        ///        Replaces any previously set point lights.
        bool (*set_point_lights)(struct ke_render *self,
                                 const ke_point_light *lights, uint32_t count, ke_error **out_error);

        /// @brief Uploads an array of spot lights for the current frame.
        ///        Replaces any previously set spot lights.
        bool (*set_spot_lights)(struct ke_render *self,
                                const ke_spot_light *lights, uint32_t count, ke_error **out_error);

        /// @brief Enables or disables screen-space ambient occlusion (SSAO).
        ///        When enabled, a G-buffer pre-pass is added each frame. No-op if
        ///        the underlying renderer does not support SSAO.
        bool (*set_ssao)(struct ke_render *self, ke_bool enabled,
                         float radius, float bias, float strength, ke_error **out_error);

        /// @brief Configures the cluster grid dimensions and light density limits.
        bool (*set_cluster_config)(struct ke_render *self, const ke_cluster_config *config, ke_error **out_error);

        /// @brief Records a textured screen-space quad into the frame packet's UI list. Coordinates
        ///        are pixels (top-left origin); the texture handle may be KE_TEXTURE_NONE for a
        ///        flat-colored quad. Drawn in the dedicated UI view (after post-fx, no depth,
        ///        alpha-blended). Sim-side recorder — actual draw happens during submit_packet.
        bool (*submit_ui_quad)(struct ke_render *self,
                               ke_texture_handle texture,
                               float dst_x, float dst_y, float dst_w, float dst_h,
                               float src_u0, float src_v0, float src_u1, float src_v1,
                               float r, float g, float b, float a, ke_error **out_error);

        /// @brief Consumes a pre-recorded frame packet and submits all draw calls to the GPU.
        ///        Must be called on the bgfx API thread, before @c frame().
        bool (*submit_packet)(struct ke_render *self, const struct ke_frame_packet *packet, ke_error **out_error);

        /// @brief Retrieves implementation-specific fatal error details (e.g., GPU crash reason).
        ///        Returns a pointer to a string that is valid until the next renderer call.
        const char *(*get_last_fatal_error)(struct ke_render *self);

        /// @brief Creates a render graph bound to this renderer. The backend implements the
        ///        graph executor (DAG sort, transient resource pool, view-id assignment); the
        ///        kernel only declares the contract (see kernel/render/render_graph.h).
        ///        Callers usually use the @c ke_render_graph_create convenience wrapper.
        ke_render_graph_handle (*create_render_graph)(struct ke_render *self);

        /// @brief Returns the renderer's *active* graph — the one whose passes
        ///        are executed every @c submit_packet. Managed/plugin code adds
        ///        new passes to this graph to plug techniques into the chain
        ///        without owning a graph instance. May return NULL if the
        ///        renderer was constructed without a default graph (rare).
        struct ke_render_graph *(*get_render_graph)(struct ke_render *self);

    } ke_render;

    typedef struct ke_render_handle
    {
        ke_render *ref;
        void (*destroy)(ke_render *self);
    } ke_render_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_RENDER_H_
