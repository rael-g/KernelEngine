#ifndef KERNEL_ENGINE_RENDER_RENDER_GRAPH_H_
#define KERNEL_ENGINE_RENDER_RENDER_GRAPH_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/render/render.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    struct ke_render;
    struct ke_frame_packet;
    struct ke_render_graph;
    struct ke_render_pass_ctx;

#define KE_ID_RENDER_GRAPH "ke_render_graph"

    // ──────────────────────────────────────────────────────────────────────────
    // Resources
    //
    // A pass declares which named resources it reads and writes; the graph
    // resolves the execution order from those declarations (topological sort
    // over the resource DAG) and allocates transient render targets, reusing
    // them across passes whose lifetimes do not overlap.
    //
    // Standard well-known names every backend must expose:
    //   "backbuffer"   — final image presented to the window (always present)
    //   "scene_color"  — main forward/deferred color (HDR when post-fx on)
    //   "depth"        — main depth buffer
    //   "normal"       — world-space normal G-buffer (when registered)
    //   "velocity"     — screen-space motion vectors (when registered)
    //
    // Plugin- and user-defined names are free-form ("user.fxaa.color",
    // "nanite.vis_buffer", "bloom.bright"). Names are case-sensitive ASCII.
    // ──────────────────────────────────────────────────────────────────────────

    /// @brief Category of resource a pass declares. Drives validation and the
    /// backend's choice of allocator (render-target pool vs. storage-buffer pool).
    typedef enum ke_resource_type
    {
        KE_RESOURCE_TYPE_TEXTURE_2D        = 0, ///< Sampled or color/depth attachment.
        KE_RESOURCE_TYPE_STORAGE_BUFFER    = 1, ///< Compute read/write buffer (added in Phase 4).
        KE_RESOURCE_TYPE_STORAGE_TEXTURE   = 2, ///< Compute writable image (added in Phase 4).
    } ke_resource_type;

    /// @brief Pixel format for texture resources. Cross-backend subset — backends
    /// reject what they cannot honor at @ref ke_render_graph_compile time so the
    /// failure surfaces synchronously, not during execution.
    typedef enum ke_resource_format
    {
        KE_FORMAT_UNDEFINED        = 0,
        KE_FORMAT_RGBA8_UNORM      = 1,
        KE_FORMAT_RGBA16F          = 2, ///< HDR scene color.
        KE_FORMAT_R32F             = 3, ///< Shadow depth / single-channel HDR.
        KE_FORMAT_D16              = 4,
        KE_FORMAT_D24S8            = 5,
        KE_FORMAT_D32F             = 6,
    } ke_resource_format;

    /// @brief How a pass accesses a declared resource. Determines barriers/state
    /// transitions and lets the executor flag illegal combinations
    /// (e.g. two passes writing the same resource).
    typedef enum ke_resource_access
    {
        KE_ACCESS_NONE             = 0,
        KE_ACCESS_SAMPLED          = 1, ///< Read-only as a sampled texture.
        KE_ACCESS_COLOR_ATTACHMENT = 2, ///< Written as a color render target.
        KE_ACCESS_DEPTH_ATTACHMENT = 3, ///< Written as a depth/stencil target.
        KE_ACCESS_STORAGE_READ     = 4, ///< Compute read (storage buffer/image).
        KE_ACCESS_STORAGE_WRITE    = 5, ///< Compute write.
        KE_ACCESS_STORAGE_RW       = 6, ///< Compute read/write.
    } ke_resource_access;

    /// @brief Sizing strategy for transient textures. Backbuffer-relative scaling
    /// lets passes (SSAO, bloom) follow window resizes without manual recreation.
    typedef enum ke_resource_size_mode
    {
        KE_SIZE_ABSOLUTE             = 0, ///< Use @c width / @c height verbatim.
        KE_SIZE_RELATIVE_TO_BACKBUFFER = 1, ///< Use @c scale_x / @c scale_y times current backbuffer.
    } ke_resource_size_mode;

    /// @brief Declares a transient resource the graph should own and recycle.
    /// Persistent resources (textures uploaded via @c ke_render.create_texture_rgba)
    /// are imported by name via @ref ke_render_graph_import_texture instead.
    typedef struct ke_resource_desc
    {
        const char *name;             ///< Unique key passes will reference. ASCII, case-sensitive.
        ke_resource_type type;
        ke_resource_format format;
        ke_resource_size_mode size_mode;
        uint32_t width;               ///< Used when @c size_mode = KE_SIZE_ABSOLUTE.
        uint32_t height;
        float scale_x;                ///< Used when @c size_mode = KE_SIZE_RELATIVE_TO_BACKBUFFER.
        float scale_y;
        uint32_t element_count;       ///< Storage-buffer element count (Phase 4; ignored for textures).
        uint32_t element_stride;      ///< Storage-buffer element size in bytes (Phase 4).
    } ke_resource_desc;

    /// @brief A pass's view onto one named resource. Bundled in arrays inside
    /// @ref ke_render_pass_params.reads / .writes so the order of declaration in
    /// user code is the order the executor sees them in.
    typedef struct ke_resource_ref
    {
        const char *name;
        ke_resource_access access;
    } ke_resource_ref;

    // ──────────────────────────────────────────────────────────────────────────
    // Passes
    // ──────────────────────────────────────────────────────────────────────────

    /// @brief Kind of work a pass performs. Drives validation: GEOMETRY passes
    /// must declare at least one COLOR or DEPTH attachment; COMPUTE passes must
    /// declare STORAGE_* accesses only; FULLSCREEN passes are GEOMETRY with the
    /// implicit fullscreen triangle (engine provides the geometry).
    typedef enum ke_pass_type
    {
        KE_PASS_GEOMETRY   = 0,
        KE_PASS_FULLSCREEN = 1,
        KE_PASS_COMPUTE    = 2,
    } ke_pass_type;

    /// @brief Recording callback the engine invokes during execution. The
    /// callback is run on ke.render with the renderer locked into the pass's
    /// target(s). User code issues draws / compute dispatches through the
    /// @c ctx accessor functions (see @ref ke_render_pass_ctx). The @c user
    /// pointer is the same value supplied at registration.
    typedef void (*ke_render_pass_record_fn)(struct ke_render_pass_ctx *ctx, void *user);

    /// @brief Per-pass registration data. The graph copies the @c reads /
    /// @c writes arrays internally, so the caller is free to release them after
    /// @ref ke_render_graph_add_pass returns. The @c name string is borrowed,
    /// not copied, so use a static literal or an allocation the graph outlives.
    typedef struct ke_render_pass_params
    {
        const char *name;                       ///< Stable identifier ("shadow.directional", "bloom.bright"…).
        ke_pass_type type;
        const ke_resource_ref *reads;           ///< May be NULL when @c reads_count = 0.
        uint32_t reads_count;
        const ke_resource_ref *writes;          ///< May be NULL when @c writes_count = 0.
        uint32_t writes_count;
        ke_render_pass_record_fn record;        ///< Required.
        void *user;                             ///< Passed to @c record verbatim.
    } ke_render_pass_params;

    // ──────────────────────────────────────────────────────────────────────────
    // Pass context (provided to record callbacks)
    //
    // The executor binds the pass's writes as targets and exposes the pass's
    // reads as queryable handles. User code never touches view-ids or
    // framebuffers directly — that's the graph's job.
    // ──────────────────────────────────────────────────────────────────────────

    /// @brief Opaque per-pass recording context. Lifetime is the call to the
    /// record callback; do not retain.
    typedef struct ke_render_pass_ctx
    {
        void *handle;

        /// @brief Returns the texture handle bound at @c name, or the None
        /// sentinel when the pass did not declare a read/write of that name.
        ke_texture_handle (*get_texture)(struct ke_render_pass_ctx *self, const char *name);

        /// @brief Returns the current backbuffer dimensions in pixels. Useful
        /// for fullscreen passes that need to write a uniform with the size.
        void (*get_backbuffer_size)(struct ke_render_pass_ctx *self, uint32_t *out_w, uint32_t *out_h);

        /// @brief Frame packet currently being executed. NULL when the graph is
        /// being run synthetically (e.g. test harness).
        const struct ke_frame_packet *(*get_frame_packet)(struct ke_render_pass_ctx *self);

        /// @brief Underlying renderer, for issuing the actual draw / compute
        /// calls. Backend-specific in practice — most passes use this to call
        /// @c submit_mesh, @c dispatch_compute, etc.
        struct ke_render *(*get_renderer)(struct ke_render_pass_ctx *self);
    } ke_render_pass_ctx;

    // ──────────────────────────────────────────────────────────────────────────
    // Graph object
    // ──────────────────────────────────────────────────────────────────────────

    /// @brief Public render-graph interface. Created via
    /// @ref ke_render_graph_create against an initialized renderer.
    ///
    /// Threading: @c add_pass / @c declare_resource / @c import_texture / @c compile
    /// must be invoked from a single thread (the thread that owns the renderer —
    /// typically ke.render during init). @c execute always runs on ke.render
    /// after the frame packet arrives. Cross-thread registration is not
    /// supported; gameplay code that wants to add a pass at runtime marshals
    /// the request through the existing resource command queue.
    typedef struct ke_render_graph
    {
        void *handle;

        /// @brief Declares a transient resource the graph allocates and recycles.
        bool (*declare_resource)(struct ke_render_graph *self, const ke_resource_desc *desc, ke_error **out_error);

        /// @brief Imports an externally-owned texture under @c name so passes
        /// can read/write it through the graph's resource system.
        bool (*import_texture)(struct ke_render_graph *self, const char *name, ke_texture_handle handle, ke_error **out_error);

        /// @brief Registers a pass. Order of registration is irrelevant —
        /// execution order is derived from the resource DAG at @c compile time.
        bool (*add_pass)(struct ke_render_graph *self, const ke_render_pass_params *params, ke_error **out_error);

        /// @brief Removes a previously-added pass by name. Sets out_error to KE_ERROR_NOT_FOUND
        /// when no pass with that name is registered. Call @c compile again afterwards.
        bool (*remove_pass)(struct ke_render_graph *self, const char *name, ke_error **out_error);

        /// @brief Topo-sorts passes, validates reads/writes, allocates transient
        /// resources, assigns backend view-ids. Must be called after any
        /// add_pass / remove_pass / declare_resource batch and before execute.
        /// Idempotent when graph topology has not changed.
        bool (*compile)(struct ke_render_graph *self, ke_error **out_error);

        /// @brief Runs all passes in resolved order, feeding each its record
        /// callback. @c packet is forwarded to passes via @c get_frame_packet
        /// and may be NULL only in tests.
        bool (*execute)(struct ke_render_graph *self, const struct ke_frame_packet *packet, ke_error **out_error);
    } ke_render_graph;

    /* ke_render_graph_handle is defined in render.h (it is the return type of the
       create_render_graph vtable slot, and only contains pointers). */

    /// @brief Convenience wrapper that delegates to @c renderer->create_render_graph.
    /// The graph holds a borrowed reference to the renderer — caller keeps ownership
    /// and must outlive it. Returns a handle whose @c ref is NULL when the renderer
    /// does not implement the graph contract or on allocation failure.
    static inline ke_render_graph_handle ke_render_graph_create(struct ke_render *renderer)
    {
        if (!renderer || !renderer->create_render_graph) {
            ke_render_graph_handle empty = {0};
            return empty;
        }
        return renderer->create_render_graph(renderer);
    }

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_RENDER_GRAPH_H_
