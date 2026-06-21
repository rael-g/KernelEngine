#ifndef KERNEL_ENGINE_RENDER_GPU_DEVICE_H_
#define KERNEL_ENGINE_RENDER_GPU_DEVICE_H_

#include <kernel_engine/render/gpu_enums.h>
#include <kernel_engine/common/error.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

// ── Opaque resource handles (uint64_t, never raw pointers) ────────────────

typedef uint64_t ke_gpu_buffer;
typedef uint64_t ke_gpu_texture;
typedef uint64_t ke_gpu_texture_view;
typedef uint64_t ke_gpu_sampler;
typedef uint64_t ke_gpu_shader_module;
typedef uint64_t ke_gpu_pipeline;
typedef uint64_t ke_gpu_bind_group_layout;
typedef uint64_t ke_gpu_bind_group;
typedef uint64_t ke_gpu_queue;
typedef uint64_t ke_gpu_fence;

// ── Forward declarations for L4 typed recording objects ───────────────────

typedef struct ke_gpu_command_encoder ke_gpu_command_encoder;
typedef struct ke_gpu_command_buffer  ke_gpu_command_buffer;
typedef struct ke_gpu_render_pass     ke_gpu_render_pass;
typedef struct ke_gpu_compute_pass    ke_gpu_compute_pass;

// ── Forward declaration ───────────────────────────────────────────────────

typedef struct ke_gpu_device ke_gpu_device;

// ══════════════════════════════════════════════════════════════════════════
// Params structs
// ══════════════════════════════════════════════════════════════════════════

typedef struct ke_gpu_buffer_params
{
    const void        *initial_data;
    size_t             size;
    ke_gpu_buffer_usage usage;
    ke_bool            mapped_at_creation;
} ke_gpu_buffer_params;

typedef struct ke_gpu_texture_params
{
    uint32_t               width;
    uint32_t               height;
    uint32_t               depth_or_array_layers;
    ke_gpu_texture_format  format;
    ke_gpu_texture_dimension dimension;
    ke_gpu_texture_usage   usage;
    uint8_t                mip_level_count;
    uint8_t                sample_count;
} ke_gpu_texture_params;

typedef struct ke_gpu_texture_view_params
{
    ke_gpu_texture_format    format;
    ke_gpu_texture_dimension dimension;
    ke_gpu_texture_aspect    aspect;
    uint8_t                  base_mip_level;
    uint8_t                  mip_level_count;
    uint8_t                  base_array_layer;
    uint8_t                  array_layer_count;
} ke_gpu_texture_view_params;

typedef struct ke_gpu_sampler_params
{
    ke_gpu_filter               min_filter;
    ke_gpu_filter               mag_filter;
    ke_gpu_sampler_mipmap_filter mipmap_filter;
    ke_gpu_address_mode         address_mode_u;
    ke_gpu_address_mode         address_mode_v;
    ke_gpu_address_mode         address_mode_w;
    float                       lod_min_clamp;
    float                       lod_max_clamp;
    ke_gpu_compare_function     compare;
    uint16_t                    max_anisotropy;
} ke_gpu_sampler_params;

typedef struct ke_gpu_shader_module_params
{
    const uint32_t *code;        ///< SPIR-V bytecode
    size_t          byte_size;
    const char     *entry_point; ///< e.g. "main"
} ke_gpu_shader_module_params;

// ── Vertex attribute / buffer layout ──────────────────────────────────────

typedef struct ke_gpu_vertex_attribute
{
    uint32_t             shader_location;
    ke_gpu_vertex_format format;
    uint64_t             offset;
} ke_gpu_vertex_attribute;

typedef struct ke_gpu_vertex_buffer_layout
{
    uint64_t                       stride;
    ke_gpu_vertex_step_mode        step_mode;
    uint32_t                       attribute_count;
    const ke_gpu_vertex_attribute *attributes;
} ke_gpu_vertex_buffer_layout;

// ── Blend state ───────────────────────────────────────────────────────────

typedef struct ke_gpu_blend_state
{
    ke_bool             blend_enabled;
    ke_gpu_blend_factor src_color;
    ke_gpu_blend_factor dst_color;
    ke_gpu_blend_op     color_op;
    ke_gpu_blend_factor src_alpha;
    ke_gpu_blend_factor dst_alpha;
    ke_gpu_blend_op     alpha_op;
    uint8_t             write_mask; ///< bitmask: bit 0=R, 1=G, 2=B, 3=A
} ke_gpu_blend_state;

// ── Depth / stencil state ─────────────────────────────────────────────────

typedef struct ke_gpu_depth_stencil_state
{
    ke_bool                 depth_test_enabled;
    ke_bool                 depth_write_enabled;
    ke_gpu_compare_function depth_compare;
    ke_bool                 stencil_test_enabled;
    ke_gpu_stencil_op       stencil_front_fail;
    ke_gpu_stencil_op       stencil_front_depth_fail;
    ke_gpu_stencil_op       stencil_front_pass;
    ke_gpu_compare_function stencil_front_compare;
    ke_gpu_stencil_op       stencil_back_fail;
    ke_gpu_stencil_op       stencil_back_depth_fail;
    ke_gpu_stencil_op       stencil_back_pass;
    ke_gpu_compare_function stencil_back_compare;
    uint8_t                 stencil_read_mask;
    uint8_t                 stencil_write_mask;
} ke_gpu_depth_stencil_state;

// ── Bind group layout ─────────────────────────────────────────────────────

typedef struct ke_gpu_bind_group_layout_entry
{
    uint32_t            binding;
    ke_gpu_shader_stage visibility;
    ke_gpu_binding_type type;
    ke_bool             has_dynamic_offset;
} ke_gpu_bind_group_layout_entry;

typedef struct ke_gpu_bind_group_layout_params
{
    uint32_t                              entry_count;
    const ke_gpu_bind_group_layout_entry *entries;
} ke_gpu_bind_group_layout_params;

// ── Bind group (instance) ─────────────────────────────────────────────────

typedef struct ke_gpu_bind_group_entry
{
    uint32_t            binding;
    ke_gpu_binding_type type;
    ke_gpu_buffer       buffer;
    uint64_t            buffer_offset;
    uint64_t            buffer_size;
    ke_gpu_texture_view texture_view;
    ke_gpu_sampler      sampler;
} ke_gpu_bind_group_entry;

typedef struct ke_gpu_bind_group_params
{
    ke_gpu_bind_group_layout      layout;
    uint32_t                      entry_count;
    const ke_gpu_bind_group_entry *entries;
} ke_gpu_bind_group_params;

// ── Render pipeline ───────────────────────────────────────────────────────

typedef struct ke_gpu_render_pipeline_params
{
    ke_gpu_shader_module             vertex_module;
    ke_gpu_shader_module             fragment_module;
    const char                      *vertex_entry;    ///< NULL → "main"
    const char                      *fragment_entry;  ///< NULL → "main"
    ke_gpu_primitive_topology        primitive_topology;
    ke_gpu_cull_mode                 cull_mode;
    ke_gpu_front_face                front_face;
    uint32_t                         vertex_buffer_count;
    const ke_gpu_vertex_buffer_layout *vertex_buffers;
    ke_gpu_blend_state               blend_state;
    ke_gpu_depth_stencil_state       depth_stencil;
    ke_gpu_bind_group_layout         bind_group_layouts[4];
    uint32_t                         bind_group_layout_count;
    ke_bool                          alpha_to_coverage_enabled;
} ke_gpu_render_pipeline_params;

// ── Compute pipeline ──────────────────────────────────────────────────────

typedef struct ke_gpu_compute_pipeline_params
{
    ke_gpu_shader_module     compute_module;
    ke_gpu_bind_group_layout bind_group_layouts[4];
    uint32_t                 bind_group_layout_count;
} ke_gpu_compute_pipeline_params;

// ── Render pass begin params ──────────────────────────────────────────────

typedef struct ke_gpu_color_attachment
{
    ke_gpu_texture_view view;
    ke_gpu_load_op      load_op;
    ke_gpu_store_op     store_op;
    ke_gpu_clear_value  clear_value;
} ke_gpu_color_attachment;

typedef struct ke_gpu_depth_stencil_attachment
{
    ke_gpu_texture_view view;
    ke_gpu_load_op      depth_load_op;
    ke_gpu_store_op     depth_store_op;
    ke_gpu_store_op     stencil_store_op;
    float               clear_depth;
    uint8_t             clear_stencil;
    ke_bool             depth_read_only;
    ke_bool             stencil_read_only;
} ke_gpu_depth_stencil_attachment;

typedef struct ke_gpu_render_pass_params
{
    const ke_gpu_color_attachment         *color_attachments;
    uint32_t                               color_attachment_count;
    const ke_gpu_depth_stencil_attachment *depth_stencil_attachment;
} ke_gpu_render_pass_params;

// ── Resource barrier ──────────────────────────────────────────────────────

typedef enum ke_gpu_barrier_type
{
    KE_GPU_BARRIER_BUFFER,
    KE_GPU_BARRIER_TEXTURE,
} ke_gpu_barrier_type;

typedef struct ke_gpu_buffer_barrier
{
    ke_gpu_buffer       buffer;
    ke_gpu_buffer_usage from_state;
    ke_gpu_buffer_usage to_state;
} ke_gpu_buffer_barrier;

typedef struct ke_gpu_texture_barrier
{
    ke_gpu_texture       texture;
    ke_gpu_texture_usage from_state;
    ke_gpu_texture_usage to_state;
} ke_gpu_texture_barrier;

typedef struct ke_gpu_barrier
{
    ke_gpu_barrier_type type;
    union {
        ke_gpu_buffer_barrier  buffer;
        ke_gpu_texture_barrier texture;
    };
} ke_gpu_barrier;

// ══════════════════════════════════════════════════════════════════════════
// ke_gpu_device — L3 vtable
//
// Fallible operations return bool and set *out_error on failure.
// Resource creation slots return KE_GPU_INVALID_HANDLE on failure.
// The backing `rp_*` / `cp_*` / `encoder_*` slots drive the L4 typed
// recording objects in gpu_commands.h; L5+ callers use those, not these.
// ══════════════════════════════════════════════════════════════════════════

typedef struct ke_gpu_device
{
    void *handle;

    // ── Queue ──────────────────────────────────────────────────────────────
    ke_gpu_queue (*get_default_queue)(struct ke_gpu_device *self);
    void (*queue_submit)(struct ke_gpu_device *self, ke_gpu_queue q,
                         ke_gpu_command_buffer *const *cmds, uint32_t cmd_count);
    void (*queue_present)(struct ke_gpu_device *self, ke_gpu_queue q);
    void (*queue_wait_idle)(struct ke_gpu_device *self, ke_gpu_queue q);

    // ── Fence (timeline) ───────────────────────────────────────────────────
    ke_gpu_fence (*create_fence)(struct ke_gpu_device *self, uint64_t initial_value);
    void (*queue_signal_fence)(struct ke_gpu_device *self, ke_gpu_queue q,
                               ke_gpu_fence f, uint64_t value);
    bool (*wait_fence)(struct ke_gpu_device *self, ke_gpu_fence f,
                       uint64_t value, uint64_t timeout_ns, ke_error **out_error);
    uint64_t (*get_fence_value)(struct ke_gpu_device *self, ke_gpu_fence f);
    void (*destroy_fence)(struct ke_gpu_device *self, ke_gpu_fence f);

    // ── Resource creation ──────────────────────────────────────────────────
    ke_gpu_buffer          (*create_buffer)(struct ke_gpu_device *self,
                                            const ke_gpu_buffer_params *p);
    ke_gpu_texture         (*create_texture)(struct ke_gpu_device *self,
                                             const ke_gpu_texture_params *p);
    ke_gpu_texture_view    (*create_texture_view)(struct ke_gpu_device *self,
                                                  ke_gpu_texture tex,
                                                  const ke_gpu_texture_view_params *p);
    ke_gpu_sampler         (*create_sampler)(struct ke_gpu_device *self,
                                             const ke_gpu_sampler_params *p);
    ke_gpu_shader_module   (*create_shader_module)(struct ke_gpu_device *self,
                                                   const ke_gpu_shader_module_params *p);
    ke_gpu_pipeline        (*create_render_pipeline)(struct ke_gpu_device *self,
                                                     const ke_gpu_render_pipeline_params *p);
    ke_gpu_pipeline        (*create_compute_pipeline)(struct ke_gpu_device *self,
                                                      const ke_gpu_compute_pipeline_params *p);
    ke_gpu_bind_group_layout (*create_bind_group_layout)(struct ke_gpu_device *self,
                                                         const ke_gpu_bind_group_layout_params *p);
    ke_gpu_bind_group      (*create_bind_group)(struct ke_gpu_device *self,
                                                const ke_gpu_bind_group_params *p);

    // ── Resource destruction ───────────────────────────────────────────────
    void (*destroy_buffer)(struct ke_gpu_device *self, ke_gpu_buffer h);
    void (*destroy_texture)(struct ke_gpu_device *self, ke_gpu_texture h);
    void (*destroy_texture_view)(struct ke_gpu_device *self, ke_gpu_texture_view h);
    void (*destroy_sampler)(struct ke_gpu_device *self, ke_gpu_sampler h);
    void (*destroy_shader_module)(struct ke_gpu_device *self, ke_gpu_shader_module h);
    void (*destroy_pipeline)(struct ke_gpu_device *self, ke_gpu_pipeline h);
    void (*destroy_bind_group_layout)(struct ke_gpu_device *self, ke_gpu_bind_group_layout h);
    void (*destroy_bind_group)(struct ke_gpu_device *self, ke_gpu_bind_group h);

    // ── Encoder (backing primitives for L4 ke_gpu_command_encoder) ────────
    void *(*encoder_create)(struct ke_gpu_device *self);
    void *(*encoder_begin_render_pass)(struct ke_gpu_device *self, void *encoder,
                                       const ke_gpu_render_pass_params *p);
    void *(*encoder_begin_compute_pass)(struct ke_gpu_device *self, void *encoder);
    void  (*encoder_pipeline_barrier)(struct ke_gpu_device *self, void *encoder,
                                      const ke_gpu_barrier *b);
    void  (*encoder_copy_buffer_to_buffer)(struct ke_gpu_device *self, void *encoder,
                                           ke_gpu_buffer src, size_t src_offset,
                                           ke_gpu_buffer dst, size_t dst_offset,
                                           size_t size);
    void  (*encoder_copy_buffer_to_texture)(struct ke_gpu_device *self, void *encoder,
                                            ke_gpu_buffer src, size_t src_offset,
                                            ke_gpu_texture dst,
                                            uint32_t dst_x, uint32_t dst_y, uint32_t dst_z,
                                            uint32_t width, uint32_t height);
    void *(*encoder_finish)(struct ke_gpu_device *self, void *encoder);
    void  (*encoder_destroy)(struct ke_gpu_device *self, void *encoder);

    // ── Render pass (backing primitives for L4 ke_gpu_render_pass) ────────
    void (*rp_set_pipeline)(struct ke_gpu_device *self, void *rp, ke_gpu_pipeline pipe);
    void (*rp_set_bind_group)(struct ke_gpu_device *self, void *rp,
                               uint32_t group_index, ke_gpu_bind_group bg,
                               const uint32_t *dynamic_offsets, uint32_t dyn_count);
    void (*rp_set_vertex_buffer)(struct ke_gpu_device *self, void *rp,
                                  uint32_t slot, ke_gpu_buffer b, size_t offset);
    void (*rp_set_index_buffer)(struct ke_gpu_device *self, void *rp,
                                 ke_gpu_buffer b, ke_gpu_index_format fmt, size_t offset);
    void (*rp_set_viewport)(struct ke_gpu_device *self, void *rp,
                             float x, float y, float w, float h,
                             float min_depth, float max_depth);
    void (*rp_set_scissor)(struct ke_gpu_device *self, void *rp,
                            int32_t x, int32_t y, uint32_t w, uint32_t h);
    void (*rp_draw)(struct ke_gpu_device *self, void *rp,
                    uint32_t vert_count, uint32_t inst_count,
                    uint32_t first_vert, uint32_t first_inst);
    void (*rp_draw_indexed)(struct ke_gpu_device *self, void *rp,
                             uint32_t idx_count, uint32_t inst_count,
                             uint32_t first_idx, int32_t base_vert, uint32_t first_inst);
    void (*rp_draw_indirect)(struct ke_gpu_device *self, void *rp,
                              ke_gpu_buffer indirect_buf, size_t offset);
    void (*rp_end)(struct ke_gpu_device *self, void *rp);

    // ── Compute pass (backing primitives for L4 ke_gpu_compute_pass) ──────
    void (*cp_set_pipeline)(struct ke_gpu_device *self, void *cp, ke_gpu_pipeline pipe);
    void (*cp_set_bind_group)(struct ke_gpu_device *self, void *cp,
                               uint32_t group_index, ke_gpu_bind_group bg,
                               const uint32_t *dynamic_offsets, uint32_t dyn_count);
    void (*cp_dispatch)(struct ke_gpu_device *self, void *cp,
                        uint32_t x, uint32_t y, uint32_t z);
    void (*cp_dispatch_indirect)(struct ke_gpu_device *self, void *cp,
                                  ke_gpu_buffer indirect_buf, size_t offset);
    void (*cp_end)(struct ke_gpu_device *self, void *cp);

    // ── Command buffer lifecycle ───────────────────────────────────────────
    void (*cmd_buffer_destroy)(struct ke_gpu_device *self, void *cmd_buf);

    // ── Mapped writes ──────────────────────────────────────────────────────
    void *(*map_buffer)(struct ke_gpu_device *self, ke_gpu_buffer h,
                        size_t offset, size_t size);
    void *(*map_buffer_write)(struct ke_gpu_device *self, ke_gpu_buffer h,
                              size_t offset, size_t size);
    void  (*unmap_buffer)(struct ke_gpu_device *self, ke_gpu_buffer h);

    // ── Capabilities ───────────────────────────────────────────────────────
    void (*get_capabilities)(struct ke_gpu_device *self, ke_gpu_capabilities *out);

    // ── Extension query ────────────────────────────────────────────────────
    /// Returns a typed extension vtable by name, or NULL if unsupported.
    const void *(*query_extension)(struct ke_gpu_device *self, const char *name);
} ke_gpu_device;

// ── Owner wrapper ──────────────────────────────────────────────────────────

typedef struct ke_gpu_device_handle
{
    ke_gpu_device *ref;
    void (*destroy)(ke_gpu_device *self);
} ke_gpu_device_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_GPU_DEVICE_H_
