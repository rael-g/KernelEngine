#ifndef KERNEL_ENGINE_RENDER_CORE_RENDER_CORE_H_
#define KERNEL_ENGINE_RENDER_CORE_RENDER_CORE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/math/math.h>
#include <kernel_engine/render/binding/resource_binder.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/render/mesh.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

typedef struct ke_render_service ke_render_service;

/// What every shader reads about the frame being drawn, under the parameter `ke_frame`. Matrices are
/// stored the way the math library stores them.
typedef struct ke_render_frame_globals
{
    float view[16];
    float proj[16];
    float view_proj[16];
    float inv_view_proj[16];
    float inv_proj[16];
    /// World position of the camera in xyz; w is 1.
    float camera_pos[4];
    /// Backbuffer width and height in pixels in xy; zw are 0.
    float viewport[4];
    /// Seconds since the first frame.
    float time;
    /// Seconds since the previous frame.
    float dt;
    float near_plane;
    float far_plane;
} ke_render_frame_globals;

/// The scene's light that every lit shader reads, under the parameter `ke_lighting`.
typedef struct ke_render_lighting
{
    /// Direction the directional light travels in xyz; w is 1 when the scene has one, else 0.
    float direction[4];
    /// Color of the directional light in rgb; a is its intensity.
    float color[4];
    /// Ambient color in rgb; a is 0.
    float ambient[4];
} ke_render_lighting;

/// Where a pass that works on the frame's color runs, given to the render graph as the pass's injection
/// point: the stages run in this order. Stages up to KE_RENDER_STAGE_HDR_POST draw in the frame's
/// color format, the later ones in its output's.
typedef enum ke_render_stage
{
    /// What the opaque stage reads: shadows, light clusters, the gbuffer.
    KE_RENDER_STAGE_PREPASS     = 0,
    KE_RENDER_STAGE_OPAQUE      = 1,
    KE_RENDER_STAGE_SKY         = 2,
    KE_RENDER_STAGE_TRANSPARENT = 3,
    KE_RENDER_STAGE_HDR_POST    = 4,
    KE_RENDER_STAGE_TONEMAP     = 5,
    KE_RENDER_STAGE_LDR_POST    = 6,
    KE_RENDER_STAGE_OVERLAY     = 7,
    KE_RENDER_STAGE_COUNT       = 8,
} ke_render_stage;

struct ke_render_service
{
    void *handle;

    /// Begins a frame: forgets the previous frame's uploads, acquires the service's render target and
    /// reads its size.
    /// @param out_view [out] Receives the view the frame is presented from; KE_GPU_INVALID_HANDLE
    ///                 when the target has nothing to draw into this frame, which then begins none.
    /// @return KE_OK, or the target's code when acquiring failed.
    ke_result (*begin_frame)(struct ke_render_service *self, ke_gpu_texture_view *out_view);
    /// Submits the uploads recorded since the frame began, before the frame's own work is submitted.
    void (*submit_uploads)(struct ke_render_service *self);
    /// Presents the render target. Succeeds doing nothing when no frame began, and fails with the
    /// target's code when presenting failed.
    ke_result (*end_frame)(struct ke_render_service *self);
    /// Draws @p source over the whole of @p pass's colour attachment, whose format is @p target_format.
    void (*blit)(struct ke_render_service *self, ke_gpu_render_pass *pass, ke_gpu_texture_view source,
                 ke_gpu_texture_format target_format);

    /// Uploads interleaved vertices and 16-bit indices to device buffers.
    /** @param key [utf8] Dedup cache key; required.
     *  @param vertices [array_of:vertex_count] Interleaved vertices.
     *  @param indices [array_of:index_count] Triangle list indices.
     *  @param out_mesh [out] Receives the handle of the uploaded mesh. */
    ke_result (*upload_mesh)(struct ke_render_service *self, const char *key,
                             const ke_mesh_vertex *vertices, uint32_t vertex_count,
                             const uint16_t *indices, uint32_t index_count,
                             ke_mesh_handle *out_mesh);
    /// [try] Resolves a mesh handle to its GPU buffers. Returns false for a
    /// handle this service never uploaded.
    /// @param out_vbo [out]
    /// @param out_ibo [out]
    /// @param out_index_count [out]
    bool (*mesh_buffers)(struct ke_render_service *self, ke_mesh_handle h,
                            ke_gpu_buffer *out_vbo, ke_gpu_buffer *out_ibo,
                            uint32_t *out_index_count);

    /** @param key [utf8] Dedup cache key; required.
     *  @param rgba [array_of:rgba_size] RGBA8 pixels in row order; width by height by four bytes.
     *  @param out_texture [out] Receives the handle of the uploaded texture. */
    ke_result (*upload_texture)(struct ke_render_service *self, const char *key,
                                uint32_t width, uint32_t height,
                                const uint8_t *rgba, size_t rgba_size,
                                ke_texture_handle *out_texture);
    /**
     * @param key [utf8] Dedup cache key; required.
     * @param metallic [default:0]
     * @param roughness [default:0.5]
     * @param albedo [default:none] KE_TEXTURE_NONE selects the white texture.
     * @param normal [default:none] KE_TEXTURE_NONE selects a flat normal.
     * @param alpha_mode [default:KE_ALPHA_MODE_OPAQUE]
     * @param alpha_cutoff [default:0.5]
     * @param ior [default:1.5]
     * @param distortion_strength [default:0.05]
     * @param shader [utf8,nullable,default:none] Authored material name; NULL/empty selects the engine default.
     * @param out_material [out] Receives the handle of the material.
     */
    ke_result (*create_material)(struct ke_render_service *self, const char *key,
                                 ke_vec4 base_color,
                                 float metallic, float roughness,
                                 ke_texture_handle albedo,
                                 ke_texture_handle normal,
                                 ke_alpha_mode alpha_mode,
                                 float alpha_cutoff,
                                 float ior,
                                 float distortion_strength,
                                 const char *shader,
                                 ke_material_handle *out_material);
    /// What the service's resource binder holds for a material handle, the argument a pass gives
    /// its bind_material; an unknown handle resolves to the built-in white material.
    ke_render_material_binding (*material_binding)(struct ke_render_service *self, ke_material_handle h);
    /// The pass bucket for a material handle, resolved from CPU-side storage —
    /// no GPU state touched.
    ke_alpha_mode (*material_alpha_mode)(struct ke_render_service *self, ke_material_handle h);
    /// The MASK discard threshold for a material handle.
    float (*material_alpha_cutoff)(struct ke_render_service *self, ke_material_handle h);

    /** @param key [utf8] Dedup cache key; required.
     *  @param faces [array_of:faces_size] Six square RGBA8 faces, in the order +X, -X, +Y, -Y, +Z, -Z.
     *  @param out_cubemap [out] Receives the handle of the uploaded cubemap. */
    ke_result (*upload_cubemap)(struct ke_render_service *self, const char *key,
                                uint32_t face_size, const uint8_t *faces, size_t faces_size,
                                ke_texture_handle *out_cubemap);
    /// The GPU view for a texture/cubemap handle.
    ke_gpu_texture_view (*texture_view)(struct ke_render_service *self, ke_texture_handle h);

    /// The backbuffer's pixel size, callable from any phase. Refreshed once per
    /// frame at begin_frame, so a caller earlier in the tick reads the previous
    /// frame's size.
    /// @param out_w [out]
    /// @param out_h [out]
    void (*backbuffer_size)(struct ke_render_service *self, uint32_t *out_w, uint32_t *out_h);

    /// Records a buffer upload, submitted by submit_uploads.
    void (*upload)(struct ke_render_service *self, ke_gpu_buffer buffer,
                   uint64_t offset, const void *data, size_t size);

    /// Returns the pipeline for this exact params state, compiling it on first
    /// request.
    ke_gpu_pipeline (*get_or_create_pipeline)(struct ke_render_service *self,
                                              const ke_gpu_render_pipeline_params *params);

    /// The authored-material shader name a material handle was created with
    /// (see create_material's `shader`).
    const char *(*material_shader)(struct ke_render_service *self, ke_material_handle h);

    /// Adds a reference to a mesh, keeping it resident.
    void (*retain_mesh)(struct ke_render_service *self, ke_mesh_handle h);
    /// Drops a reference to a mesh, freeing it at zero.
    void (*release_mesh)(struct ke_render_service *self, ke_mesh_handle h);
    /// Adds a reference to a texture, keeping it resident.
    void (*retain_texture)(struct ke_render_service *self, ke_texture_handle h);
    /// Drops a reference to a texture, freeing it at zero.
    void (*release_texture)(struct ke_render_service *self, ke_texture_handle h);
    /// Adds a reference to a material, keeping it resident.
    void (*retain_material)(struct ke_render_service *self, ke_material_handle h);
    /// Drops a reference to a material, freeing it at zero.
    void (*release_material)(struct ke_render_service *self, ke_material_handle h);

    /**
     * [try] Path-keyed probe for a resident mesh upload: on a hit, retains and
     * writes the resident handle to `out`. try_get_texture also serves cubemaps
     * (shared cache).
     * @param key [utf8] Dedup cache key.
     * @param out [out] Receives the resident handle on a cache hit.
     */
    bool (*try_get_mesh)(struct ke_render_service *self, const char *key, ke_mesh_handle *out);
    /**
     * [try] Path-keyed probe for a resident texture upload.
     * @param key [utf8] Dedup cache key.
     * @param out [out] Receives the resident handle on a cache hit.
     */
    bool (*try_get_texture)(struct ke_render_service *self, const char *key, ke_texture_handle *out);
    /**
     * [try] Path-keyed probe for a resident material.
     * @param key [utf8] Dedup cache key.
     * @param out [out] Receives the resident handle on a cache hit.
     */
    bool (*try_get_material)(struct ke_render_service *self, const char *key, ke_material_handle *out);

    /// The built-in 1×1 white texture, resolvable everywhere a neutral albedo
    /// is wanted.
    ke_texture_handle (*white_texture)(struct ke_render_service *self);

    /// Resolves a shader by logical NAME + STAGE to a device-ready module. Its file is read once;
    /// on a thread that may not wait for the read, the call returns while the read goes on, and a
    /// later call with the same name and stage collects it.
    /// @param out_module [out] Receives the module.
    /// @return KE_OK; KE_RESULT_PENDING while the read goes on; KE_RESULT_NOT_FOUND when no shader
    ///         has that name, or the device's code when it rejects the module.
    ke_result (*load_shader)(struct ke_render_service *self, const char *name,
                             ke_gpu_shader_stage stage, ke_gpu_shader_module *out_module);

    /// Replaces the frame globals and records their upload; a shader reads them as `ke_frame`.
    void (*set_frame_globals)(struct ke_render_service *self, const ke_render_frame_globals *globals);
    /// The frame globals last set, zero before the first.
    const ke_render_frame_globals *(*frame_globals)(struct ke_render_service *self);
    /// Replaces the scene's light and records its upload; a shader reads it as `ke_lighting`.
    void (*set_lighting)(struct ke_render_service *self, const ke_render_lighting *lighting);
    /// The scene's light last set, zero before the first.
    const ke_render_lighting *(*lighting)(struct ke_render_service *self);

    /// The resource binder the service was created with, through which a pass brings its resources
    /// to its shaders; the service has given it `ke_frame`, `ke_lighting` and the `ke_samp_*` samplers.
    ke_render_resource_binder *(*resource_binder)(struct ke_render_service *self);

    /// Texel format of the backbuffer, the format a pipeline drawing into it declares.
    ke_gpu_texture_format (*backbuffer_format)(struct ke_render_service *self);

};

/// [owner]
typedef struct ke_render_service_handle
{
    ke_render_service *ref;
    void (*destroy)(ke_render_service *self);
} ke_render_service_handle;

#ifdef __cplusplus
}
#endif

#endif
