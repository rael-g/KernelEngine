#ifndef KERNEL_ENGINE_RENDER_CORE_RENDER_CORE_H_
#define KERNEL_ENGINE_RENDER_CORE_RENDER_CORE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/binding/resource_binder.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/handles.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

/// Opaque: the per-pass recording context.
typedef struct ke_render_pass_ctx ke_render_pass_ctx;

typedef struct ke_render_service ke_render_service;

typedef enum ke_render_resource_type
{
    KE_RENDER_RESOURCE_TEXTURE = 0,
    KE_RENDER_RESOURCE_BUFFER  = 1,
} ke_render_resource_type;

typedef enum ke_render_size_mode
{
    KE_RENDER_SIZE_ABSOLUTE               = 0,
    KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER = 1,
} ke_render_size_mode;

typedef struct ke_render_resource_desc
{
    const char             *name;
    ke_render_resource_type type;
    ke_gpu_texture_format   format;
    ke_render_size_mode     size_mode;
    uint32_t                width;   ///< Read when size_mode is ABSOLUTE.
    uint32_t                height;
    float                   scale_x; ///< Read when size_mode is RELATIVE_TO_BACKBUFFER.
    float                   scale_y;
    /// Per-resource clear color.
    float                   clear_value[4];
} ke_render_resource_desc;

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

/// A pass's declared resource I/O by name.
typedef struct ke_render_pass_io
{
    /// Optional name the pass's render or compute pass is labeled with; copied when the pass
    /// begins.
    const char        *name;
    const char *const *reads;
    uint32_t           reads_count;
    const char *const *writes;
    uint32_t           writes_count;
    /// When non-zero, color attachments load their existing contents instead of
    /// clearing.
    uint32_t           load;
} ke_render_pass_io;

struct ke_render_service
{
    void *handle;

    /// Declares a transient resource the service allocates and recycles.
    /// @return The tag-component cid to place in a pass's access_list.
    ke_component_id (*declare)(struct ke_render_service *self,
                               const ke_render_resource_desc *desc, ke_error **out_error);
    /// Imports an externally-owned texture under `name`.
    /// @return Its tag-component cid.
    ke_component_id (*import_texture)(struct ke_render_service *self, const char *name,
                                      ke_gpu_texture tex, ke_error **out_error);
    /// Mints a tag cid under `name` with no GPU payload.
    ke_component_id (*import_tag)(struct ke_render_service *self, const char *name,
                                  ke_error **out_error);
    /// Publishes an externally-owned GPU buffer under `name` for another pass to
    /// bind by name.
    ke_component_id (*import_buffer)(struct ke_render_service *self, const char *name,
                                     ke_gpu_buffer buffer, uint64_t size, ke_error **out_error);
    /// @return The tag cid minted for `name`, or KE_COMPONENT_INVALID.
    ke_component_id (*cid)(struct ke_render_service *self, const char *name);

    /// Opens a pass's recording context, from inside a render system's body.
    struct ke_render_pass_ctx *(*begin_pass)(struct ke_render_service *self,
                                             const ke_render_pass_io *io);
    /// Closes a recording context opened by begin_pass.
    void (*end_pass)(struct ke_render_service *self, struct ke_render_pass_ctx *ctx);

    /// Acquires the service's render target as the backbuffer (a built-in resource named
    /// "backbuffer") and clears the per-pass command slot table. Returns false when the target
    /// has nothing to draw into this frame, with out_error set when acquiring it failed.
    ke_bool (*begin_frame)(struct ke_render_service *self, ke_error **out_error);
    /// Submits the populated command slots in ascending slot order, then presents the render
    /// target. Returns false when no frame began, or with out_error set when presenting failed.
    ke_bool (*end_frame)(struct ke_render_service *self, ke_error **out_error);

    /// Uploads interleaved vertices and 16-bit indices to device buffers.
    /// @return The handle of the uploaded mesh.
    /** @param key [utf8] Dedup cache key; required. */
    ke_mesh_handle (*upload_mesh)(struct ke_render_service *self, const char *key,
                                  const void *vertices, size_t vertices_size,
                                  const uint16_t *indices, uint32_t index_count,
                                  ke_error **out_error);
    /// [try] Resolves a mesh handle to its GPU buffers. Returns false for a
    /// handle this service never uploaded.
    /// @param out_vbo [out]
    /// @param out_ibo [out]
    /// @param out_index_count [out]
    ke_bool (*mesh_buffers)(struct ke_render_service *self, ke_mesh_handle h,
                            ke_gpu_buffer *out_vbo, ke_gpu_buffer *out_ibo,
                            uint32_t *out_index_count);

    /// The color a pass clears its color attachments to (begin_render
    /// LOAD_OP_CLEAR).
    void (*set_clear_color)(struct ke_render_service *self, float r, float g, float b, float a);

    /** @param key [utf8] Dedup cache key; required. */
    ke_texture_handle (*upload_texture)(struct ke_render_service *self, const char *key,
                                        uint32_t width, uint32_t height,
                                        const void *rgba, ke_error **out_error);
    /**
     * @param key [utf8] Dedup cache key; required.
     * @param shader [utf8,nullable] Authored material name; NULL/empty selects the engine default.
     */
    ke_material_handle (*create_material)(struct ke_render_service *self, const char *key,
                                          const float *base_color,
                                          float metallic, float roughness,
                                          ke_texture_handle albedo,
                                          ke_texture_handle normal,
                                          ke_alpha_mode alpha_mode,
                                          float alpha_cutoff,
                                          float ior,
                                          float distortion_strength,
                                          const char *shader,
                                          ke_error **out_error);
    /// What the service's resource binder holds for a material handle, the argument a pass gives
    /// its bind_material; an unknown handle resolves to the built-in white material.
    ke_render_material_binding (*material_binding)(struct ke_render_service *self, ke_material_handle h);
    /// The pass bucket for a material handle, resolved from CPU-side storage —
    /// no GPU state touched.
    ke_alpha_mode (*material_alpha_mode)(struct ke_render_service *self, ke_material_handle h);
    /// The MASK discard threshold for a material handle.
    float (*material_alpha_cutoff)(struct ke_render_service *self, ke_material_handle h);

    /** @param key [utf8] Dedup cache key; required. */
    ke_texture_handle (*upload_cubemap)(struct ke_render_service *self, const char *key,
                                        uint32_t face_size, const void *faces,
                                        ke_error **out_error);
    /// The GPU view for a texture/cubemap handle.
    ke_gpu_texture_view (*texture_view)(struct ke_render_service *self, ke_texture_handle h);

    /// The GPU view of a declared transient resource, by name.
    ke_gpu_texture_view (*resource_view)(struct ke_render_service *self, const char *name);
    /// The raw GPU texture behind a declared resource, for the copy operations
    /// that take a texture rather than a view.
    ke_gpu_texture (*resource_texture)(struct ke_render_service *self, const char *name);
    /// The GPU buffer published under `name` via import_buffer.
    ke_gpu_buffer (*resource_buffer)(struct ke_render_service *self, const char *name);
    /// The size (bytes) of the buffer published under `name`.
    uint64_t (*resource_buffer_size)(struct ke_render_service *self, const char *name);

    /// The backbuffer's pixel size, callable from any phase. Refreshed once per
    /// frame at begin_frame, so a caller earlier in the tick reads the previous
    /// frame's size.
    /// @param out_w [out]
    /// @param out_h [out]
    void (*backbuffer_size)(struct ke_render_service *self, uint32_t *out_w, uint32_t *out_h);

    /// Records a buffer upload to be flushed single-threaded at end_frame
    /// (before submit).
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
    ke_bool (*try_get_mesh)(struct ke_render_service *self, const char *key, ke_mesh_handle *out);
    /**
     * [try] Path-keyed probe for a resident texture upload.
     * @param key [utf8] Dedup cache key.
     * @param out [out] Receives the resident handle on a cache hit.
     */
    ke_bool (*try_get_texture)(struct ke_render_service *self, const char *key, ke_texture_handle *out);
    /**
     * [try] Path-keyed probe for a resident material.
     * @param key [utf8] Dedup cache key.
     * @param out [out] Receives the resident handle on a cache hit.
     */
    ke_bool (*try_get_material)(struct ke_render_service *self, const char *key, ke_material_handle *out);

    /// The built-in 1×1 white texture, resolvable everywhere a neutral albedo
    /// is wanted.
    ke_texture_handle (*white_texture)(struct ke_render_service *self);

    /// Resolves a shader by logical NAME + STAGE to a device-ready module.
    ke_gpu_shader_module (*load_shader)(struct ke_render_service *self, const char *name,
                                        ke_gpu_shader_stage stage, ke_error **out_error);

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

    /// Counts the times the targets declared relative to the backbuffer were recreated, which
    /// `begin_frame` does when the backbuffer changes size. A pass that keeps something made from
    /// a declared target's view, a bind group for instance, rebuilds it when the count changes.
    uint32_t (*resource_generation)(struct ke_render_service *self);
};

typedef struct ke_render_service_handle
{
    ke_render_service *ref;
    void (*destroy)(ke_render_service *self);
} ke_render_service_handle;

#ifdef __cplusplus
}
#endif

#endif
