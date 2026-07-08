#ifndef KERNEL_ENGINE_RENDER_GPU_ENUMS_H_
#define KERNEL_ENGINE_RENDER_GPU_ENUMS_H_

#include <kernel_engine/common/types.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

// ── Index format ──────────────────────────────────────────────────────────

typedef enum ke_gpu_index_format
{
    KE_GPU_INDEX_FORMAT_UINT16,
    KE_GPU_INDEX_FORMAT_UINT32,
} ke_gpu_index_format;

// ── Texture format ────────────────────────────────────────────────────────

typedef enum ke_gpu_texture_format
{
    KE_GPU_TEXTURE_FORMAT_INVALID          = 0,
    KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
    KE_GPU_TEXTURE_FORMAT_RGBA8_SRGB,
    KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM,
    KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
    KE_GPU_TEXTURE_FORMAT_R32_FLOAT,
    KE_GPU_TEXTURE_FORMAT_R16_FLOAT,
    KE_GPU_TEXTURE_FORMAT_D16_UNORM,
    KE_GPU_TEXTURE_FORMAT_D24_UNORM_S8_UINT,
    KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
    KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT,
    KE_GPU_TEXTURE_FORMAT_RGBA32_FLOAT,
    KE_GPU_TEXTURE_FORMAT_RG32_FLOAT,
    KE_GPU_TEXTURE_FORMAT_R8_UNORM,
    KE_GPU_TEXTURE_FORMAT_BC1_RGBA_UNORM,
    KE_GPU_TEXTURE_FORMAT_BC3_RGBA_UNORM,
    KE_GPU_TEXTURE_FORMAT_BC5_RG_UNORM,
    KE_GPU_TEXTURE_FORMAT_BC7_RGBA_UNORM,
} ke_gpu_texture_format;

// ── Texture dimension ─────────────────────────────────────────────────────

typedef enum ke_gpu_texture_dimension
{
    KE_GPU_TEXTURE_DIM_1D,
    KE_GPU_TEXTURE_DIM_2D,
    KE_GPU_TEXTURE_DIM_3D,
    KE_GPU_TEXTURE_DIM_CUBE,
} ke_gpu_texture_dimension;

// ── Texture aspect (bitmask) ──────────────────────────────────────────────

typedef uint32_t ke_gpu_texture_aspect;
#define KE_GPU_TEXTURE_ASPECT_COLOR   (1u << 0)
#define KE_GPU_TEXTURE_ASPECT_DEPTH   (1u << 1)
#define KE_GPU_TEXTURE_ASPECT_STENCIL (1u << 2)

// ── Texture usage (bitmask) — values match WGPUTextureUsage ──────────────

typedef uint32_t ke_gpu_texture_usage;
#define KE_GPU_TEXTURE_USAGE_COPY_SRC     0x01u
#define KE_GPU_TEXTURE_USAGE_COPY_DST     0x02u
#define KE_GPU_TEXTURE_USAGE_SAMPLED      0x04u  ///< TextureBinding
#define KE_GPU_TEXTURE_USAGE_STORAGE      0x08u  ///< StorageBinding
#define KE_GPU_TEXTURE_USAGE_COLOR_ATTACH 0x10u  ///< RenderAttachment
#define KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH 0x20u  ///< also maps to RenderAttachment in WebGPU

// ── Buffer usage (bitmask) — values match WGPUBufferUsage ────────────────

typedef uint32_t ke_gpu_buffer_usage;
#define KE_GPU_BUFFER_USAGE_MAP_READ  0x0001u
#define KE_GPU_BUFFER_USAGE_MAP_WRITE 0x0002u
#define KE_GPU_BUFFER_USAGE_COPY_SRC  0x0004u
#define KE_GPU_BUFFER_USAGE_COPY_DST  0x0008u
#define KE_GPU_BUFFER_USAGE_INDEX     0x0010u
#define KE_GPU_BUFFER_USAGE_VERTEX    0x0020u
#define KE_GPU_BUFFER_USAGE_UNIFORM   0x0040u
#define KE_GPU_BUFFER_USAGE_STORAGE   0x0080u
#define KE_GPU_BUFFER_USAGE_INDIRECT  0x0100u

// ── Shader stage (bitmask) — values match WGPUShaderStage ────────────────

typedef uint32_t ke_gpu_shader_stage;
#define KE_GPU_SHADER_STAGE_VERTEX   0x1u
#define KE_GPU_SHADER_STAGE_FRAGMENT 0x2u
#define KE_GPU_SHADER_STAGE_COMPUTE  0x4u

// ── Load / store op ───────────────────────────────────────────────────────

typedef enum ke_gpu_load_op
{
    KE_GPU_LOAD_OP_LOAD,
    KE_GPU_LOAD_OP_CLEAR,
    KE_GPU_LOAD_OP_DONT_CARE,
} ke_gpu_load_op;

typedef enum ke_gpu_store_op
{
    KE_GPU_STORE_OP_STORE,
    KE_GPU_STORE_OP_DONT_CARE,
} ke_gpu_store_op;

// ── Sampler filters / addressing ──────────────────────────────────────────

typedef enum ke_gpu_filter
{
    KE_GPU_FILTER_NEAREST,
    KE_GPU_FILTER_LINEAR,
} ke_gpu_filter;

typedef enum ke_gpu_sampler_mipmap_filter
{
    KE_GPU_SAMPLER_MIPMAP_NEAREST,
    KE_GPU_SAMPLER_MIPMAP_LINEAR,
} ke_gpu_sampler_mipmap_filter;

typedef enum ke_gpu_address_mode
{
    KE_GPU_ADDRESS_MODE_REPEAT,
    KE_GPU_ADDRESS_MODE_MIRRORED_REPEAT,
    KE_GPU_ADDRESS_MODE_CLAMP_TO_EDGE,
    KE_GPU_ADDRESS_MODE_CLAMP_TO_BORDER,
} ke_gpu_address_mode;

// ── Compare function ──────────────────────────────────────────────────────

typedef enum ke_gpu_compare_function
{
    KE_GPU_COMPARE_UNDEFINED = 0, ///< No comparison (default for samplers without shadow compare)
    KE_GPU_COMPARE_NEVER,
    KE_GPU_COMPARE_LESS,
    KE_GPU_COMPARE_EQUAL,
    KE_GPU_COMPARE_LESS_EQUAL,
    KE_GPU_COMPARE_GREATER,
    KE_GPU_COMPARE_NOT_EQUAL,
    KE_GPU_COMPARE_GREATER_EQUAL,
    KE_GPU_COMPARE_ALWAYS,
} ke_gpu_compare_function;

// ── Primitive topology ────────────────────────────────────────────────────

typedef enum ke_gpu_primitive_topology
{
    KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
    KE_GPU_PRIMITIVE_TOPOLOGY_LINE_LIST,
    KE_GPU_PRIMITIVE_TOPOLOGY_LINE_STRIP,
    KE_GPU_PRIMITIVE_TOPOLOGY_POINT_LIST,
} ke_gpu_primitive_topology;

// ── Cull mode ─────────────────────────────────────────────────────────────

typedef enum ke_gpu_cull_mode
{
    KE_GPU_CULL_MODE_NONE,
    KE_GPU_CULL_MODE_FRONT,
    KE_GPU_CULL_MODE_BACK,
} ke_gpu_cull_mode;

// ── Front face ────────────────────────────────────────────────────────────

typedef enum ke_gpu_front_face
{
    KE_GPU_FRONT_FACE_CCW,
    KE_GPU_FRONT_FACE_CW,
} ke_gpu_front_face;

// ── Blend factor / operation ──────────────────────────────────────────────

typedef enum ke_gpu_blend_factor
{
    KE_GPU_BLEND_FACTOR_ZERO,
    KE_GPU_BLEND_FACTOR_ONE,
    KE_GPU_BLEND_FACTOR_SRC_ALPHA,
    KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
    KE_GPU_BLEND_FACTOR_DST_ALPHA,
    KE_GPU_BLEND_FACTOR_ONE_MINUS_DST_ALPHA,
    KE_GPU_BLEND_FACTOR_SRC_COLOR,
    KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_COLOR,
    KE_GPU_BLEND_FACTOR_DST_COLOR,
    KE_GPU_BLEND_FACTOR_ONE_MINUS_DST_COLOR,
} ke_gpu_blend_factor;

typedef enum ke_gpu_blend_op
{
    KE_GPU_BLEND_OP_ADD,
    KE_GPU_BLEND_OP_SUBTRACT,
    KE_GPU_BLEND_OP_REVERSE_SUBTRACT,
    KE_GPU_BLEND_OP_MIN,
    KE_GPU_BLEND_OP_MAX,
} ke_gpu_blend_op;

// ── Stencil operation ─────────────────────────────────────────────────────

typedef enum ke_gpu_stencil_op
{
    KE_GPU_STENCIL_OP_KEEP,
    KE_GPU_STENCIL_OP_ZERO,
    KE_GPU_STENCIL_OP_REPLACE,
    KE_GPU_STENCIL_OP_INVERT,
    KE_GPU_STENCIL_OP_INCREMENT_CLAMP,
    KE_GPU_STENCIL_OP_DECREMENT_CLAMP,
} ke_gpu_stencil_op;

// ── Vertex step mode ──────────────────────────────────────────────────────

typedef enum ke_gpu_vertex_step_mode
{
    KE_GPU_VERTEX_STEP_MODE_VERTEX,
    KE_GPU_VERTEX_STEP_MODE_INSTANCE,
} ke_gpu_vertex_step_mode;

// ── Vertex format ─────────────────────────────────────────────────────────

typedef enum ke_gpu_vertex_format
{
    KE_GPU_VERTEX_FORMAT_FLOAT32X2,
    KE_GPU_VERTEX_FORMAT_FLOAT32X3,
    KE_GPU_VERTEX_FORMAT_FLOAT32X4,
    KE_GPU_VERTEX_FORMAT_SINT16X2,
    KE_GPU_VERTEX_FORMAT_SINT16X4,
    KE_GPU_VERTEX_FORMAT_UINT8X4_UNORM,
    KE_GPU_VERTEX_FORMAT_UINT8X4,
} ke_gpu_vertex_format;

// ── Binding type (bind group entries) ─────────────────────────────────────

typedef enum ke_gpu_binding_type
{
    KE_GPU_BINDING_TYPE_BUFFER,
    KE_GPU_BINDING_TYPE_SAMPLER,
    KE_GPU_BINDING_TYPE_TEXTURE,
    KE_GPU_BINDING_TYPE_STORAGE_BUFFER,          ///< read-write storage (compute only)
    KE_GPU_BINDING_TYPE_STORAGE_TEXTURE,
    KE_GPU_BINDING_TYPE_READONLY_STORAGE_BUFFER, ///< read-only storage (usable in fragment)
    KE_GPU_BINDING_TYPE_DEPTH_TEXTURE,           ///< depth-format texture, sampled/texel-fetched (e.g. deferred G-buffer depth)
} ke_gpu_binding_type;

// ── Clear value ───────────────────────────────────────────────────────────

typedef union ke_gpu_clear_value
{
    float color[4];
    struct { float depth; uint8_t stencil; } depth_stencil;
} ke_gpu_clear_value;

// ── Capabilities ──────────────────────────────────────────────────────────

/// Shader source language a device accepts. Query via
/// `ke_gpu_device::shader_language`; the shader-build layer compiles to it.
typedef enum ke_gpu_shader_language
{
    KE_GPU_SHADER_LANG_WGSL  = 0,
    KE_GPU_SHADER_LANG_SPIRV = 1,
    KE_GPU_SHADER_LANG_MSL   = 2,
    KE_GPU_SHADER_LANG_DXIL  = 3,
} ke_gpu_shader_language;

typedef struct ke_gpu_capabilities
{
    uint32_t max_texture_dimension_2d;
    uint32_t max_texture_array_layers;
    uint32_t max_bind_groups;
    uint32_t max_vertex_attributes;
    uint32_t max_vertex_buffers;
    uint32_t max_uniform_buffer_size;
    uint32_t max_storage_buffer_size;
    uint32_t max_compute_workgroup_size_x;
    uint32_t max_compute_workgroup_size_y;
    uint32_t max_compute_workgroup_size_z;
    ke_bool  supports_bindless;
    ke_bool  supports_mesh_shaders;
    ke_bool  supports_ray_tracing;
} ke_gpu_capabilities;

#define KE_GPU_INVALID_HANDLE UINT64_MAX

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_GPU_ENUMS_H_
