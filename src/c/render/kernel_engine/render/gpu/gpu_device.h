#ifndef KERNEL_ENGINE_RENDER_GPU_DEVICE_H_
#define KERNEL_ENGINE_RENDER_GPU_DEVICE_H_

#include <kernel_engine/render/gpu/gpu_enums.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/render/gpu/ndc_convention.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

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

typedef struct ke_gpu_command_encoder ke_gpu_command_encoder;
typedef struct ke_gpu_command_buffer  ke_gpu_command_buffer;
typedef struct ke_gpu_render_pass     ke_gpu_render_pass;
typedef struct ke_gpu_compute_pass    ke_gpu_compute_pass;

typedef struct ke_gpu_device ke_gpu_device;

/// A shader module failed to compile/validate (source rejected by the backend).
extern const ke_error_type KE_ERROR_GPU_SHADER_COMPILATION;

/// A resource creation call (buffer, bind group, ...) was rejected by backend
/// validation, e.g. a buffer or binding range exceeding a device limit. The
/// device limit is backend-specific. The caller that requested the resource
/// decides how to react.
extern const ke_error_type KE_ERROR_GPU_RESOURCE_CREATION;



typedef struct ke_gpu_buffer_params
{
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
    const void        *initial_data;
    size_t             size;
    ke_gpu_buffer_usage usage;
    bool               mapped_at_creation;
} ke_gpu_buffer_params;

typedef struct ke_gpu_texture_params
{
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
    uint32_t                 width;
    uint32_t                 height;
    uint32_t                 depth_or_array_layers;
    ke_gpu_texture_format    format;
    ke_gpu_texture_dimension dimension;
    ke_gpu_texture_usage     usage;
    uint8_t                  mip_level_count;
    uint8_t                  sample_count;
    const void              *initial_data;      ///< Optional. Tightly-packed RGBA8 pixels (mip 0 only).
    uint32_t                 initial_data_size; ///< Byte size of initial_data.
} ke_gpu_texture_params;

typedef struct ke_gpu_texture_view_params
{
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
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
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
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
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
    const void *code;        ///< shader bytes in the device's accepted language
                             ///< (query ke_gpu_device::shader_language); WGSL text
                             ///< or SPIR-V binary etc.
    size_t      byte_size;   ///< size in bytes (excluding any text terminator)
} ke_gpu_shader_module_params;

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

typedef struct ke_gpu_blend_state
{
    bool                blend_enabled;
    ke_gpu_blend_factor src_color;
    ke_gpu_blend_factor dst_color;
    ke_gpu_blend_op     color_op;
    ke_gpu_blend_factor src_alpha;
    ke_gpu_blend_factor dst_alpha;
    ke_gpu_blend_op     alpha_op;
    uint8_t             write_mask; ///< bitmask: bit 0=R, 1=G, 2=B, 3=A
} ke_gpu_blend_state;

typedef struct ke_gpu_depth_stencil_state
{
    bool                    depth_test_enabled;
    bool                    depth_write_enabled;
    ke_gpu_compare_function depth_compare;
    bool                    stencil_test_enabled;
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

typedef struct ke_gpu_bind_group_layout_entry
{
    uint32_t            binding;
    ke_gpu_shader_stage visibility;
    ke_gpu_binding_type type;
    bool                has_dynamic_offset;
    /// For TEXTURE bindings: KE_GPU_TEXTURE_DIM_CUBE selects a cubemap binding;
    /// any other value (incl. zero-init) is a 2D texture.
    ke_gpu_texture_dimension view_dimension;
} ke_gpu_bind_group_layout_entry;

typedef struct ke_gpu_bind_group_layout_params
{
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
    uint32_t                              entry_count;
    const ke_gpu_bind_group_layout_entry *entries;
} ke_gpu_bind_group_layout_params;

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
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
    ke_gpu_bind_group_layout      layout;
    uint32_t                      entry_count;
    const ke_gpu_bind_group_entry *entries;
} ke_gpu_bind_group_params;

typedef struct ke_gpu_render_pipeline_params
{
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
    ke_gpu_shader_module             vertex_module;
    ke_gpu_shader_module             fragment_module;
    const char                      *vertex_entry;         ///< NULL → "main"
    const char                      *fragment_entry;       ///< NULL → "main"
    ke_gpu_primitive_topology        primitive_topology;
    ke_gpu_cull_mode                 cull_mode;
    ke_gpu_front_face                front_face;
    uint32_t                         vertex_buffer_count;
    const ke_gpu_vertex_buffer_layout *vertex_buffers;
    ke_gpu_blend_state               blend_state;
    ke_gpu_depth_stencil_state       depth_stencil;
    ke_gpu_bind_group_layout         bind_group_layouts[4];
    uint32_t                         bind_group_layout_count;
    bool                             alpha_to_coverage_enabled;
    ke_gpu_texture_format            color_target_formats[8];
    uint32_t                         color_target_count;
} ke_gpu_render_pipeline_params;

typedef struct ke_gpu_compute_pipeline_params
{
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
    ke_gpu_shader_module     compute_module;
    const char              *compute_entry;
    ke_gpu_bind_group_layout bind_group_layouts[4];
    uint32_t                 bind_group_layout_count;
} ke_gpu_compute_pipeline_params;

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
    bool                depth_read_only;
    bool                stencil_read_only;
} ke_gpu_depth_stencil_attachment;

typedef struct ke_gpu_render_pass_params
{
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
    const ke_gpu_color_attachment         *color_attachments;
    uint32_t                               color_attachment_count;
    const ke_gpu_depth_stencil_attachment *depth_stencil_attachment;
} ke_gpu_render_pass_params;

typedef struct ke_gpu_command_encoder_params
{
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
} ke_gpu_command_encoder_params;

typedef struct ke_gpu_compute_pass_params
{
    /// Optional name shown for this object by capture and validation tools; copied by the call.
    const char *label;
} ke_gpu_compute_pass_params;

typedef struct ke_gpu_device
{
    void *handle;

    ke_gpu_queue (*get_default_queue)(struct ke_gpu_device *self);
    void (*queue_submit)(struct ke_gpu_device *self, ke_gpu_queue q,
                         ke_gpu_command_buffer *const *cmds, uint32_t cmd_count);
    /// Runs this device's event pump without blocking: delivers the callbacks of work that has
    /// completed since the last pump (create_render_pipeline_async, map_buffer_read).
    void (*queue_poll)(struct ke_gpu_device *self, ke_gpu_queue q);
    void (*queue_wait_idle)(struct ke_gpu_device *self, ke_gpu_queue q);

    ke_gpu_fence (*create_fence)(struct ke_gpu_device *self, uint64_t initial_value);
    void (*queue_signal_fence)(struct ke_gpu_device *self, ke_gpu_queue q,
                               ke_gpu_fence f, uint64_t value);
    bool (*wait_fence)(struct ke_gpu_device *self, ke_gpu_fence f,
                       uint64_t value, uint64_t timeout_ns, ke_error **out_error);
    uint64_t (*get_fence_value)(struct ke_gpu_device *self, ke_gpu_fence f);
    void (*destroy_fence)(struct ke_gpu_device *self, ke_gpu_fence f);

    ke_gpu_buffer          (*create_buffer)(struct ke_gpu_device *self,
                                            const ke_gpu_buffer_params *p,
                                            ke_error **out_error);
    ke_gpu_texture         (*create_texture)(struct ke_gpu_device *self,
                                             const ke_gpu_texture_params *p);
    ke_gpu_texture_view    (*create_texture_view)(struct ke_gpu_device *self,
                                                  ke_gpu_texture tex,
                                                  const ke_gpu_texture_view_params *p);
    ke_gpu_sampler         (*create_sampler)(struct ke_gpu_device *self,
                                             const ke_gpu_sampler_params *p);
    ke_gpu_shader_module   (*create_shader_module)(struct ke_gpu_device *self,
                                                   const ke_gpu_shader_module_params *p,
                                                   ke_error **out_error);
    ke_gpu_pipeline        (*create_render_pipeline)(struct ke_gpu_device *self,
                                                     const ke_gpu_render_pipeline_params *p);
    ke_gpu_pipeline        (*create_compute_pipeline)(struct ke_gpu_device *self,
                                                      const ke_gpu_compute_pipeline_params *p);
    ke_gpu_bind_group_layout (*create_bind_group_layout)(struct ke_gpu_device *self,
                                                         const ke_gpu_bind_group_layout_params *p);
    ke_gpu_bind_group      (*create_bind_group)(struct ke_gpu_device *self,
                                                const ke_gpu_bind_group_params *p,
                                                ke_error **out_error);

    void (*destroy_buffer)(struct ke_gpu_device *self, ke_gpu_buffer h);
    void (*destroy_texture)(struct ke_gpu_device *self, ke_gpu_texture h);
    void (*destroy_texture_view)(struct ke_gpu_device *self, ke_gpu_texture_view h);
    void (*destroy_sampler)(struct ke_gpu_device *self, ke_gpu_sampler h);
    void (*destroy_shader_module)(struct ke_gpu_device *self, ke_gpu_shader_module h);
    /// Releases a pipeline made by create_render_pipeline or create_render_pipeline_async.
    void (*destroy_pipeline)(struct ke_gpu_device *self, ke_gpu_pipeline h);
    void (*destroy_bind_group_layout)(struct ke_gpu_device *self, ke_gpu_bind_group_layout h);
    void (*destroy_bind_group)(struct ke_gpu_device *self, ke_gpu_bind_group h);

    /// Creates a command encoder. p may be NULL, which creates it unlabeled.
    ke_gpu_command_encoder *(*create_command_encoder)(struct ke_gpu_device *self,
                                                      const ke_gpu_command_encoder_params *p);

    void (*write_buffer)(struct ke_gpu_device *self, ke_gpu_buffer h,
                         uint64_t offset, const void *data, size_t size);

    void *(*map_buffer)(struct ke_gpu_device *self, ke_gpu_buffer h,
                        size_t offset, size_t size);
    void *(*map_buffer_write)(struct ke_gpu_device *self, ke_gpu_buffer h,
                              size_t offset, size_t size);
    void  (*unmap_buffer)(struct ke_gpu_device *self, ke_gpu_buffer h);

    void (*get_capabilities)(struct ke_gpu_device *self, ke_gpu_capabilities *out);

    /// Returns a typed extension vtable by name, or NULL if unsupported.
    const void *(*query_extension)(struct ke_gpu_device *self, const char *name);

    /// Shader source language this device accepts in create_shader_module.
    ke_gpu_shader_language (*shader_language)(struct ke_gpu_device *self);

    /// Clip-space convention this backend expects projections built in.
    ke_ndc_convention (*get_ndc_convention)(struct ke_gpu_device *self);

    /// Kicks a background pipeline compile — the driver compiles off the
    /// caller's thread; `on_ready` fires later (during this device's normal
    /// event pump, e.g. at queue_poll) with the finished pipeline, or
    /// KE_GPU_INVALID_HANDLE on failure. No caching and no fallback.
    void (*create_render_pipeline_async)(struct ke_gpu_device *self,
                                         const ke_gpu_render_pipeline_params *p,
                                         void (*on_ready)(ke_gpu_pipeline pso, void *user),
                                         void *user);

    /// Blocks until every pipeline compile kicked via
    /// create_render_pipeline_async has invoked its on_ready callback. Call
    /// before destroying anything an in-flight callback might still write
    /// into. A no-op if nothing is pending.
    void (*flush_pipeline_compiles)(struct ke_gpu_device *self);

    /// Starts mapping [offset, offset + size) of a buffer created with
    /// KE_GPU_BUFFER_USAGE_MAP_READ for reading. `on_ready` fires later, during this device's
    /// normal event pump (queue_poll, queue_wait_idle), with `ok` true when the range is
    /// readable through map_buffer until unmap_buffer, and false when the mapping failed.
    /// Submit the work that writes the buffer before calling.
    void (*map_buffer_read)(struct ke_gpu_device *self, ke_gpu_buffer h,
                            size_t offset, size_t size,
                            void (*on_ready)(ke_gpu_buffer buffer, bool ok, void *user),
                            void *user);

    /// Releases a pipeline made by create_compute_pipeline.
    void (*destroy_compute_pipeline)(struct ke_gpu_device *self, ke_gpu_pipeline h);
} ke_gpu_device;

typedef struct ke_gpu_device_handle
{
    ke_gpu_device *ref;
    void (*destroy)(ke_gpu_device *self);
} ke_gpu_device_handle;

#ifdef __cplusplus
}
#endif

#endif
