#ifndef KERNEL_ENGINE_RENDER_GRAPH_RENDER_GRAPH_H_
#define KERNEL_ENGINE_RENDER_GRAPH_RENDER_GRAPH_H_

#include <kernel_engine/completion/completion.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_render_graph ke_render_graph;
typedef struct ke_render_graph_ctx ke_render_graph_ctx;

/// [id] A resource of the frame being declared; valid until the next begin_frame.
typedef uint32_t ke_render_graph_resource;
/// [id] A pass of the frame being declared; valid until the next begin_frame.
typedef uint32_t ke_render_graph_pass;
/// [id] A resource kept past its frame by export_resource, until release_export.
typedef uint64_t ke_render_graph_export;

/// The null resource.
#define KE_RENDER_GRAPH_RESOURCE_INVALID 0u

/// What a resource is.
typedef enum ke_render_graph_resource_kind {
    KE_RENDER_GRAPH_RESOURCE_TEXTURE = 0,
    KE_RENDER_GRAPH_RESOURCE_BUFFER = 1,
    /// Holds no memory: reading and writing it only orders passes.
    KE_RENDER_GRAPH_RESOURCE_TOKEN = 2,
    /// A ray tracing acceleration structure; a graph without ray tracing refuses it.
    KE_RENDER_GRAPH_RESOURCE_ACCELERATION_STRUCTURE = 3,
} ke_render_graph_resource_kind;

/// How a texture's size is given.
typedef enum ke_render_graph_size_class {
    /// width and height in texels.
    KE_RENDER_GRAPH_SIZE_ABSOLUTE = 0,
    /// scale_x and scale_y of the frame's output.
    KE_RENDER_GRAPH_SIZE_OUTPUT_RELATIVE = 1,
    /// scale_x and scale_y of the resource relative_to.
    KE_RENDER_GRAPH_SIZE_RESOURCE_RELATIVE = 2,
} ke_render_graph_size_class;

/// [bag] A texture made for one frame.
typedef struct ke_render_graph_texture_desc {
    /// [utf8] Shown by capture and validation tools.
    const char *name;
    ke_gpu_texture_format format;
    ke_render_graph_size_class size_class;
    /// Texels, for KE_RENDER_GRAPH_SIZE_ABSOLUTE.
    uint32_t width;
    /// Texels, for KE_RENDER_GRAPH_SIZE_ABSOLUTE.
    uint32_t height;
    /// The factor of the width it is relative to, for a relative size class.
    float scale_x;
    /// The factor of the height it is relative to, for a relative size class.
    float scale_y;
    /// The resource whose size it follows, for KE_RENDER_GRAPH_SIZE_RESOURCE_RELATIVE.
    ke_render_graph_resource relative_to;
    /// At least one.
    uint32_t mip_levels;
    /// At least one.
    uint32_t array_layers;
    /// At least one; above one, the texture is multisampled.
    uint32_t samples;
    /// Whether its mips are generated from mip 0 after the last pass of the frame that writes it.
    bool generate_mips;
} ke_render_graph_texture_desc;

/// [bag] A buffer made for one frame.
typedef struct ke_render_graph_buffer_desc {
    /// [utf8] Shown by capture and validation tools.
    const char *name;
    /// Greater than zero.
    uint64_t size;
} ke_render_graph_buffer_desc;

/// How a pass uses a resource.
typedef enum ke_render_graph_usage {
    KE_RENDER_GRAPH_USAGE_SAMPLED = 0,
    KE_RENDER_GRAPH_USAGE_STORAGE_READ = 1,
    KE_RENDER_GRAPH_USAGE_STORAGE_WRITE = 2,
    KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT = 3,
    KE_RENDER_GRAPH_USAGE_DEPTH_READ = 4,
    KE_RENDER_GRAPH_USAGE_DEPTH_WRITE = 5,
    /// Read as an attachment of the same render pass.
    KE_RENDER_GRAPH_USAGE_INPUT_ATTACHMENT = 6,
    /// The single-sampled target a multisampled attachment resolves into.
    KE_RENDER_GRAPH_USAGE_RESOLVE = 7,
    KE_RENDER_GRAPH_USAGE_COPY_SRC = 8,
    KE_RENDER_GRAPH_USAGE_COPY_DST = 9,
    KE_RENDER_GRAPH_USAGE_VERTEX = 10,
    KE_RENDER_GRAPH_USAGE_INDEX = 11,
    KE_RENDER_GRAPH_USAGE_INDIRECT = 12,
    KE_RENDER_GRAPH_USAGE_UNIFORM = 13,
    /// Presented once the frame ends.
    KE_RENDER_GRAPH_USAGE_PRESENT = 14,
    /// Its bytes are handed to the pass's readback when the frame retires.
    KE_RENDER_GRAPH_USAGE_READBACK = 15,
    KE_RENDER_GRAPH_USAGE_AS_BUILD = 16,
    KE_RENDER_GRAPH_USAGE_AS_READ = 17,
    KE_RENDER_GRAPH_USAGE_TOKEN_READ = 18,
    KE_RENDER_GRAPH_USAGE_TOKEN_WRITE = 19,
} ke_render_graph_usage;

/// What an attachment holds when its pass starts.
typedef enum ke_render_graph_load {
    KE_RENDER_GRAPH_LOAD_KEEP = 0,
    KE_RENDER_GRAPH_LOAD_CLEAR = 1,
    KE_RENDER_GRAPH_LOAD_DONT_CARE = 2,
} ke_render_graph_load;

/// [value] One use of a resource by a pass.
typedef struct ke_render_graph_use {
    ke_render_graph_resource resource;
    ke_render_graph_usage usage;
    /// The first mip used.
    uint32_t base_mip;
    /// How many mips; zero means every mip from base_mip.
    uint32_t mip_count;
    /// The first array layer used.
    uint32_t base_layer;
    /// How many layers; zero means every layer from base_layer.
    uint32_t layer_count;
    /// The format the pass views the texture in, such as the sRGB alias of a UNORM one; the texture's own
    /// format when it is KE_GPU_TEXTURE_FORMAT_INVALID.
    ke_gpu_texture_format view_format;
    /// For an attachment.
    ke_render_graph_load load;
    /// The colour a cleared colour attachment starts with.
    float clear_color[4];
    /// The depth a cleared depth attachment starts with.
    float clear_depth;
    /// The stencil a cleared depth attachment starts with.
    uint32_t clear_stencil;
} ke_render_graph_use;

/// What a pass records.
typedef enum ke_render_graph_pass_type {
    KE_RENDER_GRAPH_PASS_RASTER = 0,
    KE_RENDER_GRAPH_PASS_COMPUTE = 1,
    KE_RENDER_GRAPH_PASS_COPY = 2,
} ke_render_graph_pass_type;

/// The queue a pass would rather run on; a graph may run every pass on the graphics queue.
typedef enum ke_render_graph_queue {
    KE_RENDER_GRAPH_QUEUE_GRAPHICS = 0,
    KE_RENDER_GRAPH_QUEUE_ASYNC_COMPUTE = 1,
    KE_RENDER_GRAPH_QUEUE_TRANSFER = 2,
} ke_render_graph_queue;

/// Records a pass, possibly on another thread and after add_pass returned, through @p ctx only.
/// @param user [context] Forwarded from the pass's desc.
/// @return KE_OK, or the code the frame's execution fails with.
typedef ke_result (*ke_render_graph_record_fn)(void *user, ke_render_graph_ctx *ctx);

/// Whether a pass runs this frame; asked once, at compile.
/// @param user [context] Forwarded from the pass's desc.
typedef bool (*ke_render_graph_condition_fn)(void *user);

/// Receives the bytes of a resource the pass declared READBACK, once the frame retires.
/// @param user [context] Forwarded from the pass's desc.
/// @param bytes [borrowed,array_of:size] Valid during the call.
typedef void (*ke_render_graph_readback_fn)(void *user, ke_render_graph_resource resource, const void *bytes, size_t size);

/// [bag] A pass of the frame.
typedef struct ke_render_graph_pass_desc {
    /// [utf8] Shown by capture and validation tools; copied by the call.
    const char *name;
    ke_render_graph_pass_type type;
    ke_render_graph_queue queue;
    /// Orders the passes: a use refers to the last write of its resource by a pass earlier in the order of
    /// injection point, then declaration, and passes no dependency orders run with the lower point first.
    uint32_t injection_point;
    /// Whether the pass runs even when nothing it writes is read.
    bool side_effect;
    /// [array_of:use_count] Copied by the call.
    const ke_render_graph_use *uses;
    uint32_t use_count;
    /// [closure:user] Records the pass.
    ke_render_graph_record_fn record;
    /// [closure:user,optional] NULL runs the pass every frame.
    ke_render_graph_condition_fn condition;
    /// [closure:user,optional] Required when a use is READBACK.
    ke_render_graph_readback_fn readback;
    /// [context] Forwarded to record, condition and readback.
    void *user;
} ke_render_graph_pass_desc;

/// [interface] What a pass's record sees: what it records into and the resources it declared.
typedef struct ke_render_graph_ctx {
    void *handle;

    /// The encoder a copy pass records into.
    /// @return [borrowed] Valid during the record call; NULL in a raster or compute pass.
    ke_gpu_command_encoder *(*encoder)(ke_render_graph_ctx *self);

    /// The render pass a raster pass records into, begun by the graph with the attachments the pass
    /// declared, loaded and cleared as declared, and ended by it after the record.
    /// @return [borrowed] Valid during the record call; NULL in a compute or copy pass.
    ke_gpu_render_pass *(*render_pass)(ke_render_graph_ctx *self);

    /// The compute pass a compute pass records into, begun and ended by the graph.
    /// @return [borrowed] Valid during the record call; NULL in a raster or copy pass.
    ke_gpu_compute_pass *(*compute_pass)(ke_render_graph_ctx *self);

    /// The texture behind @p resource, which the pass declared.
    /// @return The texture; KE_GPU_INVALID_HANDLE for a resource the pass did not declare.
    ke_gpu_texture (*texture)(ke_render_graph_ctx *self, ke_render_graph_resource resource);

    /// The view of @p resource for the pass's use of it.
    /// @return The view; KE_GPU_INVALID_HANDLE for a resource the pass did not declare.
    ke_gpu_texture_view (*texture_view)(ke_render_graph_ctx *self, ke_render_graph_resource resource);

    /// The buffer behind @p resource, which the pass declared.
    /// @return The buffer; KE_GPU_INVALID_HANDLE for a resource the pass did not declare.
    ke_gpu_buffer (*buffer)(ke_render_graph_ctx *self, ke_render_graph_resource resource);
    /// The size in bytes of the buffer behind @p resource, which the pass declared.
    /// @return The size; zero for a resource the pass did not declare.
    uint64_t (*buffer_size)(ke_render_graph_ctx *self, ke_render_graph_resource resource);
} ke_render_graph_ctx;

/// [interface] The passes of a frame and the resources between them, declared each frame, then compiled
/// into an order, a lifetime for every resource and the transitions between uses, and executed.
typedef struct ke_render_graph {
    void *handle;

    /// Starts declaring a frame whose output is @p output_width by @p output_height; what the previous
    /// frame declared is forgotten, its exports kept.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a zero size; KE_RESULT_NOT_SUPPORTED while the
    ///         previous frame executes.
    ke_result (*begin_frame)(ke_render_graph *self, uint32_t output_width, uint32_t output_height);

    /// Declares a texture made for this frame.
    /// @param desc [borrowed] Read during the call.
    /// @param out_resource [out] Receives the resource; KE_RENDER_GRAPH_RESOURCE_INVALID on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a desc with no meaning; KE_RESULT_NOT_SUPPORTED for a
    ///         texture the graph cannot make, such as one whose mips it would generate; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*create_texture)(ke_render_graph *self, const ke_render_graph_texture_desc *desc, ke_render_graph_resource *out_resource);

    /// Declares a buffer made for this frame.
    /// @param desc [borrowed] Read during the call.
    /// @param out_resource [out] Receives the resource; KE_RENDER_GRAPH_RESOURCE_INVALID on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a zero size; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*create_buffer)(ke_render_graph *self, const ke_render_graph_buffer_desc *desc, ke_render_graph_resource *out_resource);

    /// Declares a token, which orders the passes that use it and holds nothing.
    /// @param name [borrowed,utf8] Copied by the call.
    /// @param out_resource [out] Receives the resource; KE_RENDER_GRAPH_RESOURCE_INVALID on failure.
    /// @return KE_OK; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*create_token)(ke_render_graph *self, const char *name, ke_render_graph_resource *out_resource);

    /// Declares a texture made outside the graph, such as the swapchain's, which the frame leaves in the
    /// state of @p final_usage.
    /// @param out_resource [out] Receives the resource; KE_RENDER_GRAPH_RESOURCE_INVALID on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an invalid texture or view; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*import_texture)(ke_render_graph *self, ke_gpu_texture texture, ke_gpu_texture_view view, ke_gpu_texture_format format,
                                uint32_t width, uint32_t height, ke_render_graph_usage final_usage, ke_render_graph_resource *out_resource);

    /// Declares a buffer made outside the graph.
    /// @param out_resource [out] Receives the resource; KE_RENDER_GRAPH_RESOURCE_INVALID on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an invalid buffer; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*import_buffer)(ke_render_graph *self, ke_gpu_buffer buffer, uint64_t size, ke_render_graph_resource *out_resource);

    /// Keeps @p resource past this frame, as it is once the frame executed, such as a history buffer; a
    /// later frame declares it again with import_export.
    /// @param out_export [out] Receives the kept resource.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a token or an unknown resource; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*export_resource)(ke_render_graph *self, ke_render_graph_resource resource, ke_render_graph_export *out_export);

    /// Declares in this frame a resource an earlier frame exported.
    /// @param out_resource [out] Receives the resource; KE_RENDER_GRAPH_RESOURCE_INVALID on failure.
    /// @return KE_OK; KE_RESULT_NOT_FOUND for an export released or never made; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*import_export)(ke_render_graph *self, ke_render_graph_export exported, ke_render_graph_resource *out_resource);

    /// Frees a kept resource once no executing frame uses it.
    void (*release_export)(ke_render_graph *self, ke_render_graph_export exported);

    /// Declares a pass.
    /// @param desc [borrowed] Read during the call.
    /// @param out_pass [out] Receives the pass.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null record, an unknown resource, a READBACK use
    ///         without a readback or a usage the resource's kind has no meaning for; KE_RESULT_NOT_SUPPORTED
    ///         for a resource or a usage the graph does not offer, such as an acceleration structure
    ///         without ray tracing;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*add_pass)(ke_render_graph *self, const ke_render_graph_pass_desc *desc, ke_render_graph_pass *out_pass);

    /// Orders the passes by their dependencies, then by injection point and declaration; drops every pass
    /// whose writes nothing reads unless it has a side effect, writes an export or an imported resource;
    /// decides when each resource is made and freed and the transition before each use.
    /// @return KE_OK; KE_RESULT_GENERAL for a cycle, the passes named in the log; the code of a failed
    ///         condition.
    ke_result (*compile)(ke_render_graph *self);

    /// Records the compiled passes and submits them in order.
    /// @param out_completion [out] Receives the frame's execution, which carries the first failure of a
    ///        record; the caller releases it.
    /// @return KE_OK; KE_RESULT_NOT_SUPPORTED before compile; the code of the device that refused a resource.
    ke_result (*execute)(ke_render_graph *self, ke_completion **out_completion);
} ke_render_graph;

/// [owner]
typedef struct ke_render_graph_handle {
    ke_render_graph *ref;
    void (*destroy)(ke_render_graph *self);
} ke_render_graph_handle;

#ifdef __cplusplus
}
#endif

#endif
