#pragma once

#include <kernel_engine/render/render_graph.h>
#include "render_context.hpp"
#include <gpu_types.hpp>

#include <string>
#include <unordered_map>
#include <vector>


namespace kernel_engine::render::core
{

class CoreRenderer;

// ── RenderGraphImpl ───────────────────────────────────────────────────────
//
// First-cut executor for `ke_render_graph`. Holds passes and named resources,
// resolves execution order via Kahn topological sort over the resource DAG,
// assigns sequential bgfx view-ids on compile, and walks the compiled list on
// execute.
//
// Scope deliberately kept narrow for the Phase-2 commit:
//   - One color (or depth) attachment per pass — MRT and multi-attachment
//     merging come with the first migrated pass that needs them.
//   - Transient resources own their texture for the graph's lifetime (no
//     lifetime-overlap reuse pool yet — tracked as TODO inline). Memory
//     footprint is therefore "sum of all declared resources" until that lands.
//   - No compute passes; declaring KE_PASS_COMPUTE fails compile until Phase 4
//     wires the compute primitives. The pass type is parsed and stored.
//   - No multi-graph isolation against the same renderer; behavior is defined
//     for a single graph instance at a time, which matches every current
//     use-case.

class RenderGraphImpl
{
public:
    explicit RenderGraphImpl(CoreRenderer* renderer, ke_allocator* allocator);
    ~RenderGraphImpl();

    /// Wires the vtable returned to user code. Owns this — destruction frees it.
    ke_render_graph* ToApi();

    /// Owner-handle destroy: tears down the graph and frees its allocation.
    static void DestroyApi(ke_render_graph* self);

    // ── API surface, called via vtable trampolines ─────────────────────────
    ke_result DeclareResource(const ke_resource_desc* desc);
    ke_result ImportTexture(const char* name, ke_texture_handle handle);
    ke_result AddPass(const ke_render_pass_params* params);
    ke_result RemovePass(const char* name);
    ke_result Compile();
    ke_result Execute(const struct ke_frame_packet* packet);

private:
    // Forward-decl so Bridge can mention Pass before its full definition.
    struct Pass;

    struct ResourceRefOwned
    {
        std::string name;
        ke_resource_access access;
    };

    struct Resource
    {
        std::string name;
        ke_resource_desc desc;             // copied verbatim from caller
        bool is_imported = false;          // imported textures vs. transient
        ke_texture_handle imported_handle{ UINT32_MAX }; // valid only when is_imported
        // Backend handles populated at compile (transient resources).
        GpuTextureHandle texture = kGpuInvalidHandle;
        GpuFrameBufferHandle framebuffer = kGpuInvalidHandle;
        // Storage buffer (compute) — populated for KE_RESOURCE_TYPE_STORAGE_BUFFER
        // resources at compile. Phase 4.1 backs them with bgfx dynamic index
        // buffers tagged BGFX_BUFFER_COMPUTE_READ_WRITE; binding stays with the
        // record callback (it has direct GpuDevice access on the internal path).
        GpuDynamicIndexBufferHandle storage_buffer = kGpuInvalidHandle;
        bool owns_storage_buffer = false;
        // True when the graph created the texture/framebuffer and must destroy
        // them. Imported textures are caller-owned; framebuffers built around
        // them are still graph-owned.
        bool owns_texture = false;
        bool owns_framebuffer = false;
    };

    // State threaded into the record callback via ke_render_pass_ctx.handle.
    // Lifetime is exactly the callback's stack frame — Execute() declares one
    // per pass per frame, so concurrent graphs on different threads are
    // isolated by construction (no static/TLS storage required).
    // Record callbacks must not retain this pointer past their return.
    struct Bridge
    {
        RenderGraphImpl* impl = nullptr;
        Pass* pass = nullptr;
        const struct ke_frame_packet* packet = nullptr;
    };

    struct Pass
    {
        std::string name;
        ke_pass_type type = KE_PASS_GEOMETRY;
        std::vector<ResourceRefOwned> reads;
        std::vector<ResourceRefOwned> writes;
        ke_render_pass_record_fn record = nullptr;
        void* user = nullptr;
        // Filled at compile.
        uint16_t view_id = UINT16_MAX;
        // For passes with a single color/depth target — the framebuffer to
        // bind. MRT will need a small vector here when we get there.
        GpuFrameBufferHandle target_fb = kGpuInvalidHandle;
    };

    // Helpers.
    Resource* FindResource(const std::string& name);
    ke_result EnsureResourceMaterialized(Resource& r);
    ke_result ReleaseAllResources();
    ke_result RecompileTopology();

    // Record-callback bridge: backend opens a ctx wired to the caller's
    // stack-resident Bridge, the user's record function queries reads/writes
    // through it, then it goes out of scope when Execute moves on.
    ke_render_pass_ctx BuildPassCtx(Bridge& bridge);

    CoreRenderer* renderer_ = nullptr;
    ke_allocator* allocator_ = nullptr;

    std::unordered_map<std::string, Resource> resources_;
    std::vector<Pass> passes_;
    std::vector<size_t> execution_order_; // indices into passes_, set at compile
    bool dirty_ = true;                   // topology changed since last compile
    uint16_t base_view_id_ = 16;          // leaves the legacy 0..7 chain alive
                                          // until Phase 3 retires it. Phase 3
                                          // will drop this offset.

    ke_render_graph api_{};               // vtable handed to user code
};

} // namespace kernel_engine::render::core
