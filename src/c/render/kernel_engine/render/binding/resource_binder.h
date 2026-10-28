#ifndef KERNEL_ENGINE_RENDER_BINDING_RESOURCE_BINDER_H_
#define KERNEL_ENGINE_RENDER_BINDING_RESOURCE_BINDER_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

/// The layout a binder built for one compiled shader; 0 is the invalid one.
typedef uint64_t ke_render_shader_layout;
/// A set of resources bound to one group of a shader; 0 is the invalid one.
typedef uint64_t ke_render_resource_set;
/// The resources of one material as a binder holds them; 0 is the invalid one.
typedef uint64_t ke_render_material_binding;

/// The value no shader layout, resource set or material binding takes.
#define KE_RENDER_BINDING_INVALID 0u

/// What a pass states about a shader binding that the shader's reflection does not carry.
typedef enum ke_render_binding_hint_flags
{
    /// The texture is bound to a depth-format view.
    KE_RENDER_BINDING_HINT_DEPTH          = 0x1u,
    /// The buffer is bound with a dynamic offset given when its set is bound.
    KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET = 0x2u,
} ke_render_binding_hint_flags;

/// A hint for the binding a shader declares under `name`.
typedef struct ke_render_binding_hint
{
    const char *name;
    uint32_t    flags;
} ke_render_binding_hint;

/// What one named parameter of a shader is bound to; only the field its type reads is used.
typedef struct ke_render_shader_binding
{
    /// The parameter's name; the uniform data of a block is named after the block.
    const char         *name;
    ke_gpu_buffer       buffer;
    uint64_t            buffer_offset;
    uint64_t            buffer_size;
    ke_gpu_texture_view texture_view;
    ke_gpu_sampler      sampler;
} ke_render_shader_binding;

/// The compiled shader a layout is built for.
typedef struct ke_render_shader_layout_params
{
    /// Logical name the shader was compiled under, as a render service's load_shader takes it.
    const char                   *shader;
    /// Bitwise OR of the KE_GPU_SHADER_STAGE_* stages the shader is compiled for.
    uint32_t                      stages;
    const ke_render_binding_hint *hints; ///< [array_of:hint_count]
    uint32_t                      hint_count;
} ke_render_shader_layout_params;

/// The data of one material, as the `mat` parameter block of a material shader reads it.
typedef struct ke_render_material_data
{
    /// Linear RGBA.
    float               base_color[4];
    float               metallic;
    float               roughness;
    /// The discard threshold; 0 draws every fragment.
    float               alpha_cutoff;
    float               ior;
    float               distortion_strength;
    ke_gpu_texture_view albedo;
    ke_gpu_texture_view normal_map;
} ke_render_material_data;

/**
 * Brings the resources of a frame to the shaders that read them. A pass names a shader's
 * parameters and never learns how they reach it: in groups, in tables indexed per draw, or any
 * other way the implementation chooses.
 */
typedef struct ke_render_resource_binder
{
    void *handle;

    /**
     * Makes `binding` the resource of every shader parameter of its name that a resource set
     * leaves out. The name is copied.
     * @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the binding has no name, or
     * KE_RESULT_OUT_OF_MEMORY when it cannot be kept.
     */
    ke_result (*provide)(struct ke_render_resource_binder *self, const ke_render_shader_binding *binding);

    /**
     * Builds the layout of a compiled shader from what the build recorded about it.
     * @param out_layout [out] Receives the layout; KE_RENDER_BINDING_INVALID on failure.
     * @return KE_OK; KE_RESULT_NOT_FOUND when the shader's record is missing, or
     * KE_RESULT_INVALID_ARGUMENT when it cannot be read or a hint names no parameter of the
     * shader, the reason logged.
     */
    ke_result (*create_shader_layout)(struct ke_render_resource_binder *self,
                                      const ke_render_shader_layout_params *params,
                                      ke_render_shader_layout *out_layout);
    /// Destroys a layout; the invalid one is ignored. A set created against it must be destroyed first.
    void (*destroy_shader_layout)(struct ke_render_resource_binder *self, ke_render_shader_layout layout);

    /**
     * Fills the bind group layouts a pipeline running the shader of `layout` declares.
     * @param out_layouts [out,array_of:capacity] Receives the layouts in the order the pipeline takes them; they stay
     * owned by the binder and live as long as `layout`.
     * @param capacity The number of entries `out_layouts` holds.
     * @param out_count [out] Receives the number of layouts written.
     * @return KE_OK, or KE_RESULT_INVALID_ARGUMENT when the layout is unknown or the shader needs
     * more than `capacity` layouts.
     */
    ke_result (*pipeline_layouts)(struct ke_render_resource_binder *self, ke_render_shader_layout layout,
                                  ke_gpu_bind_group_layout *out_layouts, uint32_t capacity,
                                  uint32_t *out_count);

    /**
     * Binds resources to one group of a shader by the names its parameters carry. A parameter left
     * out is bound to what `provide` gave under its name.
     * @param block [utf8,nullable] Name of a parameter block the shader declares; NULL selects its
     * parameters declared outside any block.
     * @param label [utf8,nullable] Name shown by capture and validation tools.
     * @param bindings [array_of:binding_count] The resources bound, each to the parameter it names.
     * @param out_set [out] Receives the set; KE_RENDER_BINDING_INVALID on failure.
     * @return KE_OK; KE_RESULT_NOT_FOUND when the shader declares no such block, or
     * KE_RESULT_INVALID_ARGUMENT when a binding names no parameter of the group, a parameter is
     * bound twice or a parameter has no resource, the reason logged.
     */
    ke_result (*create_set)(struct ke_render_resource_binder *self,
                            ke_render_shader_layout layout, const char *block,
                            const char *label, const ke_render_shader_binding *bindings,
                            uint32_t binding_count, ke_render_resource_set *out_set);
    /// Destroys a set; the invalid one is ignored.
    void (*destroy_set)(struct ke_render_resource_binder *self, ke_render_resource_set set);

    /// Makes the resources of `set` those the next draws of `pass` read, with one dynamic offset per
    /// binding hinted KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET, in the order the shader declares them.
    /// @param dynamic_offsets [array_of:dynamic_offset_count]
    void (*bind_render_set)(struct ke_render_resource_binder *self, struct ke_gpu_render_pass *pass,
                            ke_render_resource_set set, const uint32_t *dynamic_offsets,
                            uint32_t dynamic_offset_count);
    /// Makes the resources of `set` those the next dispatches of `pass` read, as bind_render_set does.
    void (*bind_compute_set)(struct ke_render_resource_binder *self, struct ke_gpu_compute_pass *pass,
                             ke_render_resource_set set, const uint32_t *dynamic_offsets,
                             uint32_t dynamic_offset_count);

    /**
     * Keeps the data of one material for the shaders that draw with it. The texture views are
     * borrowed and must outlive the binding.
     * @param out_material [out] Receives the binding; KE_RENDER_BINDING_INVALID on failure.
     * @return KE_OK, or the device's code.
     */
    ke_result (*create_material)(struct ke_render_resource_binder *self,
                                 const ke_render_material_data *data,
                                 ke_render_material_binding *out_material);
    /// Destroys a material binding; the invalid one is ignored.
    void (*destroy_material)(struct ke_render_resource_binder *self, ke_render_material_binding material);
    /// Makes `material` the one the next draws of `pass` with the shader of `layout` read. An
    /// unknown material or a shader that declares no material binds nothing.
    void (*bind_material)(struct ke_render_resource_binder *self, struct ke_gpu_render_pass *pass,
                          ke_render_shader_layout layout, ke_render_material_binding material);
} ke_render_resource_binder;

typedef struct ke_render_resource_binder_handle
{
    ke_render_resource_binder *ref;
    void (*destroy)(ke_render_resource_binder *self);
} ke_render_resource_binder_handle;

#ifdef __cplusplus
}
#endif

#endif
