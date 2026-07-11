#ifndef KERNEL_ENGINE_RENDER_CORE_RENDER_CORE_H_
#define KERNEL_ENGINE_RENDER_CORE_RENDER_CORE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/render/handles.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

// Opaque — the runtime's per-system component funnel (kernel_engine/runtime/system_ctx.h).
typedef struct ke_system_ctx ke_system_ctx;

// Opaque — the per-pass recording context (kernel_engine/render/core/pass_context.h).
// Forward-declared here so this header stays light; pass impls include the full
// definition. Mirrors how gpu_device.h forward-declares its encoder/render-pass.
typedef struct ke_render_pass_ctx ke_render_pass_ctx;

// ══════════════════════════════════════════════════════════════════════════
// L5 — Render core service
//
// Owns the transient render-target pool, the resource registry, and barrier
// tracking. It does NOT order passes: a render pass is a plain runtime system,
// and the runtime's wave-builder orders them. Each declared resource is minted
// as a zero-size tag component (its cid is placed in a pass-system's
// access_list) so a texture dependency becomes an ordinary write-before-read
// edge for the same wave-builder that orders sim systems.
// ══════════════════════════════════════════════════════════════════════════

typedef struct ke_render_core ke_render_core;

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
    uint32_t                width;   // used when size_mode = ABSOLUTE
    uint32_t                height;
    float                   scale_x; // used when size_mode = RELATIVE_TO_BACKBUFFER
    float                   scale_y;
    // Per-resource clear color. Alpha == 0 (default/zeroed) defers to the core's
    // global clear color set via set_clear_color(). Alpha != 0 uses these values.
    float                   clear_value[4];
} ke_render_resource_desc;

// A pass's declared resource I/O by name. The module turns these names into
// the access_list cids (via cid()) at register_system time; begin_pass uses the
// same names to resolve views and bind the writes as attachments.
typedef struct ke_render_pass_io
{
    const char *const *reads;
    uint32_t           reads_count;
    const char *const *writes;
    uint32_t           writes_count;
    // The frame command-buffer slot this pass records into. Each pass owns a
    // distinct slot, so passes that run in parallel append without a shared
    // counter (no atomic, no race). end_frame submits the populated slots in
    // ascending order, so the module must assign slots in dependency order
    // (a pass whose output a later pass samples gets the lower slot).
    uint32_t           cmd_slot;
    // When non-zero, color attachments load their existing contents instead of
    // clearing. An overlay pass (e.g. UI on top of the tonemapped scene) sets
    // this so it composites rather than wipes the target. Default 0 = clear.
    uint32_t           load;
} ke_render_pass_io;

struct ke_render_core
{
    void *handle;

    // ── Setup (single thread, module on_load) ─────────────────────────────
    // Declares a transient resource the core allocates and recycles; returns
    // the tag-component cid to place in pass access_lists.
    ke_component_id (*declare)(struct ke_render_core *self,
                               const ke_render_resource_desc *desc, ke_error **out_error);
    // Imports an externally-owned texture under `name`; returns its tag cid.
    ke_component_id (*import_texture)(struct ke_render_core *self, const char *name,
                                      ke_gpu_texture tex, ke_error **out_error);
    // Mints a tag cid under `name` with no GPU payload — for a pure scheduling
    // ordering dependency between two passes that isn't itself a texture/
    // buffer/bind-group (e.g. a compute pass's cull-list output another pass
    // must run after, when the actual data crosses through a different named
    // resource). Same table/cid() lookup as every other named resource.
    ke_component_id (*import_tag)(struct ke_render_core *self, const char *name,
                                  ke_error **out_error);
    // Publishes an externally-owned GPU buffer under `name` (e.g. a shadow pass's
    // light-view-proj uniform) so another pass can bind it without holding a
    // pointer to the producing pass's private state — same contract as
    // import_texture, for producer outputs that aren't a texture.
    ke_component_id (*import_buffer)(struct ke_render_core *self, const char *name,
                                     ke_gpu_buffer buffer, uint64_t size, ke_error **out_error);
    // Publishes an externally-owned GPU bind group (+ the layout it was built
    // from) under `name` (e.g. a clustered-lighting pass's light-list set). A
    // consumer building its own pipeline needs the layout at setup time; the
    // bind group instance is looked up again at draw time via resource_bind_group.
    ke_component_id (*import_bind_group)(struct ke_render_core *self, const char *name,
                                         ke_gpu_bind_group bg, ke_gpu_bind_group_layout layout,
                                         ke_error **out_error);
    // The tag cid previously minted for `name` (KE_COMPONENT_INVALID if unknown).
    ke_component_id (*cid)(struct ke_render_core *self, const char *name);

    // ── Execute (inside a render system's body) ───────────────────────────
    struct ke_render_pass_ctx *(*begin_pass)(struct ke_render_core *self,
                                             ke_system_ctx *sys,
                                             const ke_render_pass_io *io);
    void (*end_pass)(struct ke_render_core *self, struct ke_render_pass_ctx *ctx);

    // ── Frame boundary (module wires these as the first/last render systems) ─
    // begin_frame acquires the backbuffer — a built-in resource named
    // "backbuffer", auto-declared at create — and clears the per-pass command
    // slot table. end_frame submits the populated command slots in ascending
    // slot order (the module assigns slots in dependency order), then presents.
    ke_bool (*begin_frame)(struct ke_render_core *self, ke_error **out_error);
    ke_bool (*end_frame)(struct ke_render_core *self, ke_error **out_error);

    // ── Mesh resources (handle-keyed GPU buffers owned by the core) ────────
    // Uploads interleaved vertices (position float3 + normal float3) and 16-bit
    // indices to device buffers; returns a handle a ke_mesh_component references.
    // The forward pass resolves the handle to draw. KE_MESH_NONE on failure.
    // `key` (optional, may be NULL) enables dedup: a non-NULL key already resident
    // returns the existing handle with its refcount bumped, uploading nothing. NULL
    // always uploads a fresh mesh. Either way the result starts with one reference;
    // the caller balances it with release_mesh.
    ke_mesh_handle (*upload_mesh)(struct ke_render_core *self, const char *key,
                                  const void *vertices, size_t vertices_size,
                                  const uint16_t *indices, uint32_t index_count,
                                  ke_error **out_error);
    // Resolves a mesh handle to its GPU buffers (for a pass to bind + draw).
    // Returns false if the handle is unknown.
    ke_bool (*mesh_buffers)(struct ke_render_core *self, ke_mesh_handle h,
                            ke_gpu_buffer *out_vbo, ke_gpu_buffer *out_ibo,
                            uint32_t *out_index_count);

    // The color a pass clears its color attachments to (begin_render LOAD_OP_CLEAR).
    // Defaults to a dark blue; the render module sets it from its config.
    void (*set_clear_color)(struct ke_render_core *self, float r, float g, float b, float a);

    // ── Material resources (glTF base color factor × albedo texture) ──────
    // Uploads an RGBA8 texture (width*height*4 bytes, row-major). The built-in
    // white texture is available via white_texture(). KE_TEXTURE_NONE on failure.
    // `key` behaves as in upload_mesh (NULL = no dedup; a resident key returns the
    // cached handle, retained). Cubemaps share this texture cache and keyspace.
    ke_texture_handle (*upload_texture)(struct ke_render_core *self, const char *key,
                                        uint32_t width, uint32_t height,
                                        const void *rgba, ke_error **out_error);
    // Creates a material: base_color factor multiplied by the albedo texture
    // (KE_TEXTURE_NONE / handle 0 = white). Handle 0 is a built-in white material.
    // KE_MATERIAL_NONE on failure. alpha_mode/alpha_cutoff are CPU-side only (see
    // material_alpha_mode below) — they never reach the GPU material uniform.
    // ior/distortion_strength only affect the transparent-forward refraction hook
    // (meaningless outside BLEND); ior: 1.0 = no bend, 1.33 = water, 1.5 = glass.
    // distortion_strength: lateral shift of the sampled background, in
    // normalized screen space (glass vs. thick water).
    // shader_variant selects which build-time-compiled fragment shader the
    // drawing pass uses for this material (§6 Mechanism 1 proof — a real
    // shader difference resolves to a distinct PSO via get_or_create_pipeline,
    // not just different bind-group data). 0 = the pass's default/flat variant;
    // an out-of-range value resolves to 0. CPU-side only, like alpha_mode.
    // `key` behaves as in upload_mesh (NULL = no dedup; a resident key returns the
    // cached material, retained).
    ke_material_handle (*create_material)(struct ke_render_core *self, const char *key,
                                          const float *base_color, // rgba (4 floats)
                                          float metallic, float roughness,
                                          ke_texture_handle albedo,
                                          ke_texture_handle normal, // KE_TEXTURE_NONE = flat
                                          ke_alpha_mode alpha_mode,
                                          float alpha_cutoff,
                                          float ior,
                                          float distortion_strength,
                                          uint32_t shader_variant,
                                          ke_error **out_error);
    // The per-material bind-group layout (descriptor set 1) a forward pipeline
    // must declare so its set-1 bind groups (from material_bind_group) are valid.
    ke_gpu_bind_group_layout (*material_layout)(struct ke_render_core *self);
    // The set-1 bind group for a material handle; an unknown handle resolves to
    // the built-in white material (handle 0).
    ke_gpu_bind_group (*material_bind_group)(struct ke_render_core *self, ke_material_handle h);
    // The pass bucket for a material handle, resolved from CPU-side storage —
    // no GPU state touched. gbuffer skips BLEND; transparent forward skips
    // everything else. An unknown handle resolves to OPAQUE (the white material).
    ke_alpha_mode (*material_alpha_mode)(struct ke_render_core *self, ke_material_handle h);
    // The MASK discard threshold for a material handle. Meaningless outside MASK.
    float (*material_alpha_cutoff)(struct ke_render_core *self, ke_material_handle h);

    // ── Environment cubemap (skybox + image-based lighting) ──────────────
    // Uploads an RGBA8 cubemap: 6 faces of face_size×face_size, +X,-X,+Y,-Y,+Z,-Z
    // concatenated. Returns a texture handle whose view is cube-dimensioned.
    // KE_TEXTURE_NONE on failure.
    // `key` behaves as in upload_mesh (NULL = no dedup). Cubemaps live in the same
    // texture cache as upload_texture and share its keyspace.
    ke_texture_handle (*upload_cubemap)(struct ke_render_core *self, const char *key,
                                        uint32_t face_size, const void *faces,
                                        ke_error **out_error);
    // The GPU view for a texture/cubemap handle (for a pass to bind it). A stale or
    // unknown handle resolves to the built-in white texture.
    ke_gpu_texture_view (*texture_view)(struct ke_render_core *self, ke_texture_handle h);
    // The shared filtering sampler the core creates (linear, repeat).
    ke_gpu_sampler (*sampler)(struct ke_render_core *self);

    // The GPU view of a declared transient resource by name (so one pass can bind
    // another pass's output, e.g. the forward sampling the shadow map).
    // KE_GPU_INVALID_HANDLE if no resource with that name was declared.
    ke_gpu_texture_view (*resource_view)(struct ke_render_core *self, const char *name);
    // The raw GPU texture behind a declared resource — for copy_texture_to_texture,
    // which operates on textures, not views (e.g. snapshotting "hdr" into a
    // second texture a same-pass refraction read can sample without a hazard).
    // KE_GPU_INVALID_HANDLE if no resource with that name was declared.
    ke_gpu_texture (*resource_texture)(struct ke_render_core *self, const char *name);
    // The GPU buffer published under `name` via import_buffer. KE_GPU_INVALID_HANDLE
    // if no buffer with that name was published.
    ke_gpu_buffer (*resource_buffer)(struct ke_render_core *self, const char *name);
    // The size (bytes) of the buffer published under `name`. 0 if unknown.
    uint64_t (*resource_buffer_size)(struct ke_render_core *self, const char *name);
    // The GPU bind group published under `name` via import_bind_group.
    // KE_GPU_INVALID_HANDLE if no bind group with that name was published.
    ke_gpu_bind_group (*resource_bind_group)(struct ke_render_core *self, const char *name);
    // The layout the named bind group was built from (for a consumer's own
    // pipeline creation). KE_GPU_INVALID_HANDLE if unknown.
    ke_gpu_bind_group_layout (*resource_bind_group_layout)(struct ke_render_core *self, const char *name);

    // Records a buffer upload to be flushed single-threaded at end_frame (before
    // submit). Render passes call this instead of the device's write_buffer so
    // parallel passes never touch the non-thread-safe GPU queue concurrently. The
    // data is copied, so the caller's buffer need not outlive the call. Queue
    // writes are ordered before the frame's submit, so deferring is correct.
    void (*upload)(struct ke_render_core *self, ke_gpu_buffer buffer,
                   uint64_t offset, const void *data, size_t size);

    // ── PSO authority (§6 Mechanism 1) ─────────────────────────────────────
    // Returns the pipeline for this exact params state, compiling it on first
    // request. The core owns every pipeline it hands back — callers (every
    // render pass, none privileged over another) never call
    // create_render_pipeline / destroy_pipeline themselves. Two requests with
    // identical params always resolve to the same cached pipeline.
    ke_gpu_pipeline (*get_or_create_pipeline)(struct ke_render_core *self,
                                              const ke_gpu_render_pipeline_params *params);

    // The shader-variant id a material handle was created with (see
    // create_material). An unknown handle resolves to 0 (the built-in white
    // material's variant). CPU-side only, like alpha_mode/alpha_cutoff — a
    // drawing pass uses this to pick which pipeline_params to resolve via
    // get_or_create_pipeline. Appended at the tail so adding it never shifts
    // existing slot offsets.
    uint32_t (*material_shader_variant)(struct ke_render_core *self, ke_material_handle h);

    // ── Resource lifetime (refcount + path-keyed dedup) ─────────────────────
    // The core owns one cache per resource kind (mesh / texture+cubemap /
    // material). upload_*/create_material register the result there with one
    // reference; retain adds a reference, release drops one. At zero references
    // the GPU objects are destroyed and the slot recycled (a later handle into
    // the reused slot carries a new generation, so a handle kept past its
    // release no longer resolves — see handles.h). Releasing an unknown or
    // already-stale handle is a no-op.
    void (*retain_mesh)(struct ke_render_core *self, ke_mesh_handle h);
    void (*release_mesh)(struct ke_render_core *self, ke_mesh_handle h);
    void (*retain_texture)(struct ke_render_core *self, ke_texture_handle h);
    void (*release_texture)(struct ke_render_core *self, ke_texture_handle h);
    void (*retain_material)(struct ke_render_core *self, ke_material_handle h);
    void (*release_material)(struct ke_render_core *self, ke_material_handle h);

    // Path-keyed probe: on a cache hit returns true, writes the resident handle,
    // and retains it on the caller's behalf (as a keyed upload would). Lets a
    // loader skip decoding a file whose upload is already resident. `key` must be
    // non-NULL. A miss returns false and leaves *out untouched. try_get_texture
    // also serves cubemaps (shared cache).
    ke_bool (*try_get_mesh)(struct ke_render_core *self, const char *key, ke_mesh_handle *out);
    ke_bool (*try_get_texture)(struct ke_render_core *self, const char *key, ke_texture_handle *out);
    ke_bool (*try_get_material)(struct ke_render_core *self, const char *key, ke_material_handle *out);

    // The built-in 1×1 white texture, resolvable everywhere a neutral albedo is
    // wanted. Was implicitly "handle 0" before handles became generational; now
    // exposed explicitly since no literal handle value is meaningful.
    ke_texture_handle (*white_texture)(struct ke_render_core *self);
};

typedef struct ke_render_core_handle
{
    ke_render_core *ref;
    void (*destroy)(ke_render_core *self);
} ke_render_core_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_CORE_RENDER_CORE_H_
